;;;; src/deploy.lisp -- support-dapla-deploy/deploy core package
;;;;
;;;; Consfigurator properties and DEFHOST for the Stoat stack at
;;;; support.dapla.net. Stoat (formerly Revolt) is a self-hosted Discord
;;;; alternative. The stack consists of four containers: stoat (API + web
;;;; client), stoat-db (MongoDB), stoat-cache (KeyDB), and stoat-files
;;;; (S3-compatible file server). Voice (LiveKit) is out of scope.
;;;;
;;;; support-dapla-deploy.ros is a thin command wrapper; see
;;;; support-dapla-deploy.asd for the system definition and t/e2e.lisp
;;;; for the post-deploy validation suite.

(defpackage :support-dapla-deploy/deploy
  (:use :cl)
  (:import-from :consfigurator
                :defprop :defhost :run :mrun :stripln
                :remote-exists-p :write-remote-file :on-change
                :inapplicable-property)
  (:import-from :consfigurator.property.file
                :has-content :containing-directory-exists)
  (:import-from :consfigurator.property.systemd :lingering-enabled)
  (:import-from :consfigurator.property.service :reloaded)
  (:export :*service-user*
           :*home-dataset* :*home-mountpoint* :*home-dataset-keyfile*
           :*db-dataset* :*db-mountpoint* :*db-dataset-keyfile*
           :*files-dataset* :*files-mountpoint* :*files-dataset-keyfile*
           :*cache-dataset* :*cache-mountpoint* :*cache-dataset-keyfile*
           :*secrets-path* :*config-path* :*haproxy-fqdn*
           :deploy-app
           :zfs-encryption-key :zfs-dataset-mounted
           :rootless-service-account
           :images-pulled :quadlets-activated
           :cinix-write-string :service-account-uid
           :stoat-network-sections
           :stoat-db-container-sections
           :stoat-cache-container-sections
           :stoat-files-container-sections
           :stoat-container-sections
           :haproxy-vhost-config
           :quadlets-written :haproxy-vhost-written))

(in-package :support-dapla-deploy/deploy)

(defparameter *service-user* "stoat"
  "Rootless system account the quadlets run under.")
(defparameter *home-dataset* "storage/users/stoat")
(defparameter *home-mountpoint* "/var/lib/stoat")
(defparameter *home-dataset-keyfile* "/etc/zfs-keys/stoat-users.key")
(defparameter *db-dataset* "storage/containers/stoat-db")
(defparameter *db-mountpoint* "/srv/stoat/db")
(defparameter *db-dataset-keyfile* "/etc/zfs-keys/stoat-db.key")
(defparameter *files-dataset* "storage/containers/stoat-files")
(defparameter *files-mountpoint* "/srv/stoat/files"
  "Stoat file upload storage, served by the built-in S3-compatible file server.")
(defparameter *files-dataset-keyfile* "/etc/zfs-keys/stoat-files.key")
(defparameter *cache-dataset* "storage/containers/stoat-cache")
(defparameter *cache-mountpoint* "/srv/stoat/cache")
(defparameter *cache-dataset-keyfile* "/etc/zfs-keys/stoat-cache.key")
(defparameter *secrets-path* "/var/lib/stoat/.env/secrets"
  "Generated once; holds MONGO_ROOT_PASSWORD and S3_SECRET_KEY.")
(defparameter *config-path* "/var/lib/stoat/.config/stoat/Revolt.toml"
  "Stoat server configuration file (Revolt.toml format).")
(defparameter *haproxy-fqdn* "support.dapla.net")
(defparameter *haproxy-vhost-name* "support")

(defprop zfs-encryption-key :posix (path)
  "Generate a raw 32-byte ZFS encryption key at PATH via `openssl rand -out`,
   once, left alone on redeploy. Written directly by openssl to avoid binary
   corruption through shell capture and string re-encoding."
  (:desc (format nil "ZFS encryption key at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (mrun "openssl" "rand" "-out" path "32")
   (mrun "chmod" "600" path)))

(defun zfs-create-command (dataset mountpoint keyfile)
  "The `zfs create` command for DATASET at MOUNTPOINT, AES-256-GCM
   encrypted via KEYFILE."
  (if keyfile
      (format nil
       "zfs create -o mountpoint=~A -o encryption=aes-256-gcm ~
        -o keyformat=raw -o keylocation=file://~A ~A"
       mountpoint keyfile dataset)
      (format nil "zfs create -o mountpoint=~A ~A" mountpoint dataset)))

(defprop zfs-dataset-mounted :posix (dataset mountpoint &optional keyfile)
  "Ensure DATASET exists and is mounted at MOUNTPOINT. The :check verifies
   actual mount state so a post-reboot locked dataset is caught and
   remounted."
  (:desc (format nil "ZFS dataset ~A mounted at ~A~:[~; (encrypted)~]"
                  dataset mountpoint keyfile))
  (:check
   (multiple-value-bind (out err exit)
       (run :may-fail (format nil "zfs get -H -o value mounted ~A" dataset))
     (declare (ignore err))
     (and (zerop exit) (string= "yes" (stripln out)))))
  (:apply
   (if (zerop (mrun :for-exit (format nil "zfs list -H -o name ~A" dataset)))
       (progn
         (when keyfile (mrun (format nil "zfs load-key ~A" dataset)))
         (mrun (format nil "zfs mount ~A" dataset)))
       (mrun (zfs-create-command dataset mountpoint keyfile)))))

(defprop rootless-service-account :posix (username home)
  "Ensure system account USERNAME exists with home HOME, without creating
   the directory."
  (:desc (format nil "System account ~A at ~A" username home))
  (:check (zerop (mrun :for-exit "id" username)))
  (:apply (mrun "useradd" "--system" "--no-create-home"
                "--home-dir" home username)))

(defprop db-secret-file :posix (path user)
  "Generate MongoDB root password and S3 secret key via `openssl rand -hex`,
   persisted at PATH, mode 0600, owned by USER. Left alone on redeploy."
  (:desc (format nil "Stoat secrets at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (let ((db-pass   (stripln (mrun "openssl" "rand" "-hex" "32")))
         (s3-secret (stripln (mrun "openssl" "rand" "-hex" "32"))))
     (write-remote-file
      path
      (format nil
       "MONGO_INITDB_ROOT_USERNAME=stoat~%MONGO_INITDB_ROOT_PASSWORD=~A~%~
        MONGO_INITDB_DATABASE=revolt~%S3_SECRET_KEY=~A~%"
       db-pass s3-secret)
      :mode #o600)
     (mrun "chown" (format nil "~A:~A" user user) path))))

(defprop stoat-config :posix (path user fqdn secrets-path)
  "Write Revolt.toml at PATH, populated from SECRETS-PATH. Left alone on
   redeploy once present."
  (:desc (format nil "Revolt.toml at ~A" path))
  (:check (remote-exists-p path))
  (:apply
   (containing-directory-exists path)
   (let* ((secret  (uiop:read-file-string secrets-path))
          (db-pass (second
                    (uiop:split-string
                     (first (remove-if-not
                             (lambda (l) (uiop:string-prefix-p "MONGO_INITDB_ROOT_PASSWORD=" l))
                             (uiop:split-string secret :separator '(#\Newline))))
                     :separator '(#\=))))
          (s3-key  (second
                    (uiop:split-string
                     (first (remove-if-not
                             (lambda (l) (uiop:string-prefix-p "S3_SECRET_KEY=" l))
                             (uiop:split-string secret :separator '(#\Newline))))
                     :separator '(#\=)))))
     (write-remote-file
      path
      (format nil
"[info]
token = \"~A\"

[database]
mongodb = \"mongodb://stoat:~A@stoat-db:27017/revolt\"

[redis]
uri = \"redis://stoat-cache/\"

[files]
encryption_key = \"~A\"

[hosts]
app = \"https://~A\"
api = \"https://~A\"
events = \"wss://~A\"
s3 = \"https://~A\"

[api]
registration = true
"
              (stripln (mrun "openssl" "rand" "-hex" "32"))
              db-pass s3-key fqdn fqdn fqdn fqdn)
      :mode #o600)
     (mrun "chown" (format nil "~A:~A" user user) path))))

(defprop images-pulled :posix (user &rest images)
  "Pull IMAGES into USER's rootless Podman image store via `machinectl shell`.
   The command must be an absolute path; machinectl does not accept a bare
   command name after the user@ argument."
  (:desc (format nil "Podman images pulled for ~A" user))
  (:check
   (every (lambda (image)
            (zerop (mrun :for-exit
                    (format nil "machinectl shell ~A@ /usr/bin/podman image exists ~A"
                            user image))))
          images))
  (:apply
   (dolist (image images)
     (mrun (format nil "machinectl shell ~A@ /usr/bin/podman pull ~A" user image)))))

(defun cinix-write-string (sections)
  "Serialize an alist of (section-name . ((key . value) ...)) into
   INI/systemd unit-file text."
  (with-output-to-string (s)
    (dolist (section sections)
      (format s "[~A]~%" (car section))
      (dolist (kv (cdr section))
        (format s "~A=~A~%" (car kv) (cdr kv)))
      (format s "~%"))))

(defun stoat-network-sections ()
  "Cinix AST for stoat.network: internal-only network."
  '(("Network" . (("NetworkName" . "stoat")
                  ("Driver"      . "bridge")
                  ("Subnet"      . "10.89.2.36/29")
                  ("Gateway"     . "10.89.2.37")))))

(defun stoat-db-container-sections (db-mountpoint)
  "Cinix AST for stoat-db.container: mongo:6, ZFS-backed volume,
   health-checked via mongosh ping."
  `(("Unit" . (("Description" . "Stoat MongoDB database")))
    ("Container" . (("Image"           . "oci.dapla.net/library/mongo:6")
                    ("ContainerName"   . "stoat-db")
                    ("AutoUpdate"      . "registry")
                    ("EnvironmentFile" . "%S/stoat/secrets")
                    ("Volume"          . ,(format nil "~A:/data/db:Z" db-mountpoint))
                    ("Network"         . "stoat.network")
                    ("HealthCmd"       . "mongosh --quiet --eval \"db.adminCommand('ping').ok\" || exit 1")
                    ("HealthStartPeriod" . "15s")
                    ("HealthInterval"    . "30s")
                    ("HealthTimeout"     . "10s")
                    ("HealthRetries"     . "5")))
    ("Service" . (("Restart"         . "on-failure")
                  ("TimeoutStartSec" . "120")
                  ("TimeoutStopSec"  . "30")))
    ("Install" . (("WantedBy" . "default.target")))))

(defun stoat-cache-container-sections (cache-mountpoint)
  "Cinix AST for stoat-cache.container: KeyDB (Redis-compatible), ZFS-backed."
  `(("Unit" . (("Description" . "Stoat KeyDB cache")))
    ("Container" . (("Image"         . "oci.dapla.net/eqalpha/keydb:latest")
                    ("ContainerName" . "stoat-cache")
                    ("AutoUpdate"    . "registry")
                    ("Volume"        . ,(format nil "~A:/data:Z" cache-mountpoint))
                    ("Network"       . "stoat.network")
                    ("HealthCmd"     . "keydb-cli ping")
                    ("HealthStartPeriod" . "5s")
                    ("HealthInterval"    . "15s")
                    ("HealthTimeout"     . "5s")
                    ("HealthRetries"     . "5")))
    ("Service" . (("Restart"         . "on-failure")
                  ("TimeoutStartSec" . "60")
                  ("TimeoutStopSec"  . "30")))
    ("Install" . (("WantedBy" . "default.target")))))

(defun stoat-files-container-sections (files-mountpoint secrets-path)
  "Cinix AST for stoat-files.container: Stoat's built-in S3-compatible file
   server, binds to 127.0.0.1 only. Port is UID+2, per dapla.net convention."
  (let ((port (+ (service-account-uid *service-user*) *port-base* 2)))
    `(("Unit" . (("Description" . "Stoat file server")
                 ("After"       . "stoat-db.service stoat-cache.service")
                 ("Requires"    . "stoat-db.service stoat-cache.service")))
      ("Container" . (("Image"           . "oci.dapla.net/revoltchat/autumn:latest")
                      ("ContainerName"   . "stoat-files")
                      ("AutoUpdate"      . "registry")
                      ("EnvironmentFile" . ,secrets-path)
                      ("Volume"          . ,(format nil "~A:/home/autumn/files:Z"
                                                    files-mountpoint))
                      ("Network"         . "stoat.network")))
      ("Service" . (("Restart"         . "on-failure")
                    ("TimeoutStartSec" . "60")
                    ("TimeoutStopSec"  . "30")))
      ("Install" . (("WantedBy" . "default.target"))))))

(defun stoat-container-sections (config-path)
  "Cinix AST for stoat.container: main API + web client, binds to 127.0.0.1
   only, mounts Revolt.toml read-only. API port is UID, events/WebSocket
   port is UID+1, per dapla.net convention."
  (let* ((uid         (+ (service-account-uid *service-user*) *port-base*))
         (port-api    uid)
         (port-events (1+ uid)))
    `(("Unit" . (("Description" . "Stoat chat server")
                 ("After"       . "stoat-db.service stoat-cache.service stoat-files.service")
                 ("Wants"       . "network-online.target")
                 ("Requires"    . "stoat-db.service stoat-cache.service")))
      ("Container" . (("Image"         . "oci.dapla.net/revoltchat/server:latest")
                      ("ContainerName" . "stoat")
                      ("AutoUpdate"    . "registry")

                      ("Volume"        . ,(format nil "~A:/home/revolt/Revolt.toml:ro,Z"
                                                  config-path))
                      ("Network"       . "stoat.network")
                      ("Label"         . "io.containers.autoupdate=registry")
                      ("Label"           . "org.cispec.application=support-dapla-deploy")
                      ("Label"           . "org.cispec.managed-by=consfigurator")
                      ("Label"           . "org.cispec.fqdn=support.dapla.net")
                      ("Label"           . "org.cispec.service-account=stoat")))
      ("Service" . (("Restart"         . "on-failure")
                    ("TimeoutStartSec" . "120")
                    ("TimeoutStopSec"  . "30")))
      ("Install" . (("WantedBy" . "default.target"))))))

(defun haproxy-vhost-config ()
  "HAProxy vhost text for support.dapla.net. Backend ports are derived from
   the service account UID at apply time: API=UID, events=UID+1, files=UID+2,
   per dapla.net convention."
  (let* ((uid         (+ (service-account-uid *service-user*) *port-base*))
         (port-api    uid)
         (port-events (1+ uid))
         (port-files  (+ uid 2)))
    (format nil
"frontend support_http
  bind *:80
  acl host_support hdr(host) -i support.dapla.net
  redirect scheme https code 301 if host_support

frontend support_https
  bind *:443 ssl crt /etc/haproxy/certs/support.dapla.net.pem alpn h2,http/1.1
  acl host_support hdr(host) -i support.dapla.net
  acl is_websocket hdr(Upgrade) -i websocket
  http-response set-header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\"
  http-response set-header X-Content-Type-Options nosniff
  http-response set-header X-Frame-Options SAMEORIGIN
  http-response set-header Referrer-Policy strict-origin-when-cross-origin
  http-response set-header Permissions-Policy \"interest-cohort=()\"
  use_backend stoat_ws_be  if host_support is_websocket
  use_backend stoat_api_be if host_support

backend stoat_api_be
  balance roundrobin
  option httpchk GET /
  http-check expect status 200
  timeout connect 5s
  timeout server  60s
  server stoat-api 127.0.0.1:~A check inter 10s rise 2 fall 3

backend stoat_ws_be
  balance roundrobin
  option http-server-close
  option forwardfor
  timeout connect  5s
  timeout server  120s
  timeout tunnel  3600s
  http-request set-header X-Forwarded-Proto https
  server stoat-events 127.0.0.1:~A check inter 10s rise 2 fall 3

backend stoat_files_be
  balance roundrobin
  option httpchk GET /
  http-check expect status 200
  timeout connect 5s
  timeout server  60s
  server stoat-files 10.89.2.37:3003 check inter 10s rise 2 fall 3
"
            port-api port-events port-files)))

(defprop quadlets-written :posix (user home db-mountpoint files-mountpoint
                                  cache-mountpoint config-path secrets-path)
  "Write all Stoat quadlet unit files into USER's systemd container directory.
   The service account UID is read at apply time via SERVICE-ACCOUNT-UID,
   after ROOTLESS-SERVICE-ACCOUNT has run, so PublishPort is always correct."
  (:desc (format nil "Stoat quadlet units written for ~A" user))
  (:apply
   (let ((quadlet-dir (format nil "~A/.config/containers/systemd" home)))
     (containing-directory-exists (format nil "~A/stoat.network" quadlet-dir))
     (write-remote-file (format nil "~A/stoat.network" quadlet-dir)
                        (cinix-write-string (stoat-network-sections)))
     (write-remote-file (format nil "~A/stoat-db.container" quadlet-dir)
                        (cinix-write-string (stoat-db-container-sections db-mountpoint)))
     (write-remote-file (format nil "~A/stoat-cache.container" quadlet-dir)
                        (cinix-write-string (stoat-cache-container-sections cache-mountpoint)))
     (write-remote-file (format nil "~A/stoat-files.container" quadlet-dir)
                        (cinix-write-string (stoat-files-container-sections
                                             files-mountpoint secrets-path)))
     (write-remote-file (format nil "~A/stoat.container" quadlet-dir)
                        (cinix-write-string (stoat-container-sections config-path))))))

(defprop quadlets-activated :posix (user)
  "Reload USER's user-scope systemd daemon and restart the Stoat quadlet
   services in dependency order via `machinectl shell`."
  (:desc (format nil "Quadlets activated for ~A" user))
  (:apply
   (mrun (format nil "machinectl shell ~A@ /usr/bin/systemctl --user daemon-reload" user))
   (mrun (format nil
          "machinectl shell ~A@ /usr/bin/systemctl --user restart stoat-db stoat-cache stoat-files stoat"
          user))))

(defprop haproxy-vhost-written :posix ()
  "Write the HAProxy vhost config for support.dapla.net. Skipped when the
   service account does not yet exist. Reloads HAProxy only when content
   changes."
  (:desc (format nil "HAProxy vhost written for ~A" *haproxy-fqdn*))
  (:check nil)
  (:apply
   (let* ((cfg-path (format nil "/etc/haproxy/conf.d/~A.cfg" *haproxy-vhost-name*))
          (new-content (haproxy-vhost-config))
          (current (when (probe-file cfg-path) (uiop:read-file-string cfg-path))))
     (unless (equal new-content current)
       (containing-directory-exists cfg-path)
       (write-remote-file cfg-path new-content)
       (reloaded "haproxy")))))

(defhost support-host (:deploy (:local))
  "The Stoat stack's host: four AES-256-GCM-encrypted ZFS datasets (home,
   MongoDB, file storage, KeyDB cache), the rootless service account and its
   linger, the generated secrets file, Revolt.toml, pulled images, the five
   quadlet units, and the HAProxy vhost, applied in dependency order."
  (zfs-encryption-key *home-dataset-keyfile*)
  (zfs-encryption-key *db-dataset-keyfile*)
  (zfs-encryption-key *files-dataset-keyfile*)
  (zfs-encryption-key *cache-dataset-keyfile*)
  (zfs-dataset-mounted *home-dataset*  *home-mountpoint*  *home-dataset-keyfile*)
  (zfs-dataset-mounted *db-dataset*    *db-mountpoint*    *db-dataset-keyfile*)
  (zfs-dataset-mounted *files-dataset* *files-mountpoint* *files-dataset-keyfile*)
  (zfs-dataset-mounted *cache-dataset* *cache-mountpoint* *cache-dataset-keyfile*)
  (rootless-service-account *service-user* *home-mountpoint*)
  (lingering-enabled *service-user*)
  (db-secret-file *secrets-path* *service-user*)
  (stoat-config *config-path* *service-user* *haproxy-fqdn* *secrets-path*)
  (images-pulled *service-user*
                  "oci.dapla.net/library/mongo:6"
                  "oci.dapla.net/eqalpha/keydb:latest"
                  "oci.dapla.net/revoltchat/autumn:latest"
                  "oci.dapla.net/revoltchat/server:latest")
  (quadlets-written *service-user* *home-mountpoint*
                    *db-mountpoint* *files-mountpoint* *cache-mountpoint*
                    *config-path* *secrets-path*)
  (quadlets-activated *service-user*)
  (haproxy-vhost-written))


(defprop decommissioned :posix (user)
  "Tear down the support-dapla-deploy stack in least-destructive-first order.
   Steps:
     1. Stop all containers in the service account session.
     2. Remove the HAProxy vhost config and reload HAProxy.
     3. Terminate the service account login session.
     4. Disable linger so the account session does not restart.
     5. Delete the service account.
     6. Destroy all ZFS datasets (irreversible without a backup).
     7. Remove the ZFS encryption key files.
   Confirm a current rsync.net replica or snapshot exists before
   executing steps 6 and 7."
  (:desc (format nil "support-dapla-deploy decommissioned for ~~A" user))
  (:apply
   (mrun (format nil "machinectl shell ~~A@ /usr/bin/systemctl --user stop --all" user))
   (mrun "rm" "-f" (format nil "/etc/haproxy/conf.d/~~A.cfg" *haproxy-vhost-name*))
   (mrun "systemctl" "reload" "haproxy")
   (mrun "loginctl" "terminate-user" user)
   (mrun "loginctl" "disable-linger" user)
   (mrun "userdel" user)
   (mrun "zfs" "destroy" "-r" 'storage/users/stoat')
   (mrun "zfs" "destroy" "-r" 'storage/containers/stoat-db')
   (mrun "zfs" "destroy" "-r" 'storage/containers/stoat-files')
   (mrun "zfs" "destroy" "-r" 'storage/containers/stoat-cache')
   (mrun "rm" "-f" '/etc/zfs-keys/stoat-users.key')
   (mrun "rm" "-f" '/etc/zfs-keys/stoat-db.key')
   (mrun "rm" "-f" '/etc/zfs-keys/stoat-files.key')
   (mrun "rm" "-f" '/etc/zfs-keys/stoat-cache.key')))

(defun deploy-app ()
  "Provision the Stoat stack via SUPPORT-HOST (Consfigurator, :local
   connection). Aborts loudly if any property is skipped."
  (format t "~&--> Provisioning via Consfigurator (SUPPORT-HOST)...~%")
  (let ((provisioning-failed nil))
    (handler-bind ((consfigurator::skipped-properties
                     (lambda (c) (declare (ignore c))
                       (setf provisioning-failed t))))
      (support-host))
    (when provisioning-failed
      (error "SUPPORT-HOST provisioning reported failed properties ~
              (see the per-property report above). Refusing to proceed.")))
  (format t "~&--> Stoat stack provisioned. Visit https://~A~%" *haproxy-fqdn*))
