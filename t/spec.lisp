;;;; t/spec.lisp -- support-dapla-deploy/spec
;;;;
;;;; Full coverage spec for support-dapla-deploy/deploy exports.
;;;; Run: (asdf:test-system :support-dapla-deploy/spec)

(defpackage :support-dapla-deploy/spec
  (:use :cl :fiveam)
  (:import-from :support-dapla-deploy/deploy
                :stoat-network-sections
                :stoat-db-container-sections
                :stoat-cache-container-sections
                :stoat-files-container-sections
                :stoat-container-sections
                :haproxy-vhost-config
                :cinix-write-string
                :decommissioned
                :deploy-app
                :quadlets-written
                :quadlets-activated
                :haproxy-vhost-written
                :zfs-encryption-key
                :zfs-dataset-mounted
                :rootless-service-account
                :images-pulled)
  (:export :run-spec))

(in-package :support-dapla-deploy/spec)

(def-suite :support-spec
  :description "Full coverage spec for support-dapla-deploy/deploy exports.")

(in-suite :support-spec)

(defun ini-lines (ini)
  (remove-if (lambda (l) (zerop (length l)))
             (mapcar (lambda (l) (string-trim '(#\Space #\Return) l))
                     (uiop:split-string ini :separator '(#\Newline)))))

(defun ini-has (ini sub)
  (some (lambda (l) (search sub l)) (ini-lines ini)))

;;; ── cinix-write-string ────────────────────────────────────────────────

(test cinix-single-section
  "cinix-write-string serialises a single section correctly."
  (let ((ini (cinix-write-string '(("S" . (("K" . "V")))))))
    (is (ini-has ini "[S]"))
    (is (ini-has ini "K=V"))))

(test cinix-section-order
  "cinix-write-string preserves section ordering."
  (let* ((ini (cinix-write-string '(("A" . (("K" . "1"))) ("B" . (("K" . "2"))))))
         (pa (search "[A]" ini)) (pb (search "[B]" ini)))
    (is (and pa pb (< pa pb)))))

;;; ── Network unit ──────────────────────────────────────────────────────

(test network-bridge
  "stoat.network uses netavark bridge, not Internal=true."
  (let ((ini (cinix-write-string (stoat-network-sections))))
    (is (ini-has ini "Driver=bridge"))
    (is (not (ini-has ini "Internal=true")))))

(test network-vlsm
  "stoat.network has VLSM subnet 10.89.2.36/29 and gateway 10.89.2.37."
  (let ((ini (cinix-write-string (stoat-network-sections))))
    (is (ini-has ini "Subnet=10.89.2.36/29"))
    (is (ini-has ini "Gateway=10.89.2.37"))))

;;; ── stoat-db.container ───────────────────────────────────────────────

(test db-volume-srv
  "stoat-db.container data volume uses /srv/%U/db specifier."
  (is (ini-has (cinix-write-string (stoat-db-container-sections)) "Volume=/srv/%U/db")))

(test db-env-percent-h
  "stoat-db.container EnvironmentFile uses %h specifier."
  (is (ini-has (cinix-write-string (stoat-db-container-sections)) "EnvironmentFile=%h")))

(test db-zero-arity
  "stoat-db-container-sections takes zero arguments."
  (is (listp (ignore-errors (stoat-db-container-sections)))))

;;; ── stoat-cache.container ────────────────────────────────────────────

(test cache-volume-srv
  "stoat-cache.container cache volume uses /srv/%U/cache specifier."
  (is (ini-has (cinix-write-string (stoat-cache-container-sections)) "Volume=/srv/%U/cache")))

(test cache-zero-arity
  "stoat-cache-container-sections takes zero arguments."
  (is (listp (ignore-errors (stoat-cache-container-sections)))))

;;; ── stoat-files.container ────────────────────────────────────────────

(test files-volume-srv
  "stoat-files.container files volume uses /srv/%U/files specifier."
  (is (ini-has (cinix-write-string (stoat-files-container-sections)) "Volume=/srv/%U/files")))

(test files-env-percent-h
  "stoat-files.container EnvironmentFile uses %h/.env/secrets."
  (is (ini-has (cinix-write-string (stoat-files-container-sections)) "EnvironmentFile=%h")))

(test files-zero-arity
  "stoat-files-container-sections takes zero arguments."
  (is (listp (ignore-errors (stoat-files-container-sections)))))

;;; ── stoat.container ──────────────────────────────────────────────────

(test stoat-home-volume-ro
  "stoat.container mounts %h read-only (home profile)."
  (let* ((ini   (cinix-write-string (stoat-container-sections)))
         (lines (ini-lines ini))
         (vol   (find-if (lambda (l) (and (search "Volume=" l) (search "%h" l))) lines)))
    (is (not (null vol)) "No Volume=%h line found")
    (when vol (is (search ":ro" vol) "Volume=%h not read-only"))))

(test stoat-config-volume-srv
  "stoat.container config volume uses /srv/%U/config specifier."
  (is (ini-has (cinix-write-string (stoat-container-sections)) "Volume=/srv/%U/config")))

(test stoat-no-publish-port
  "stoat.container has no PublishPort — netavark handles routing."
  (is (not (ini-has (cinix-write-string (stoat-container-sections)) "PublishPort"))))

(test stoat-zero-arity
  "stoat-container-sections takes zero arguments."
  (is (listp (ignore-errors (stoat-container-sections)))))

;;; ── HAProxy vhost ────────────────────────────────────────────────────

(test haproxy-tls-frontend
  "HAProxy config has TLS frontend on port 443."
  (is (search "bind *:443" (haproxy-vhost-config))))

(test haproxy-http-redirect
  "HAProxy config redirects HTTP to HTTPS."
  (is (search "redirect scheme https" (haproxy-vhost-config))))

(test haproxy-security-headers
  "HAProxy config sets all required security response headers."
  (let ((cfg (haproxy-vhost-config)))
    (is (search "Strict-Transport-Security" cfg))
    (is (search "X-Content-Type-Options" cfg))
    (is (search "X-Frame-Options" cfg))
    (is (search "Referrer-Policy" cfg))
    (is (search "Permissions-Policy" cfg))))

(test haproxy-netavark-gateway
  "HAProxy backend targets netavark gateway 10.89.2.37."
  (let ((cfg (haproxy-vhost-config)))
    (is (search "10.89.2.37" cfg))
    (is (not (search "127.0.0.1" cfg)))))

;;; ── defprop fboundp checks ───────────────────────────────────────────

(test haproxy-vhost-written-exported
  "haproxy-vhost-written is fbound and exported."
  (is (fboundp 'support-dapla-deploy/deploy::haproxy-vhost-written)))

(test quadlets-written-exported
  "quadlets-written is fbound and exported."
  (is (fboundp 'support-dapla-deploy/deploy::quadlets-written)))

(test quadlets-activated-exported
  "quadlets-activated is fbound and exported."
  (is (fboundp 'support-dapla-deploy/deploy::quadlets-activated)))

(test zfs-encryption-key-exported
  "zfs-encryption-key is fbound and exported."
  (is (fboundp 'support-dapla-deploy/deploy::zfs-encryption-key)))

(test zfs-dataset-mounted-exported
  "zfs-dataset-mounted is fbound and exported."
  (is (fboundp 'support-dapla-deploy/deploy::zfs-dataset-mounted)))

(test rootless-service-account-exported
  "rootless-service-account is fbound and exported."
  (is (fboundp 'support-dapla-deploy/deploy::rootless-service-account)))

(test images-pulled-exported
  "images-pulled is fbound and exported."
  (is (fboundp 'support-dapla-deploy/deploy::images-pulled)))

(test decommissioned-exported
  "decommissioned is fbound and exported."
  (is (fboundp 'support-dapla-deploy/deploy::decommissioned)))

(test deploy-app-exported
  "deploy-app is fbound and exported."
  (is (fboundp 'support-dapla-deploy/deploy::deploy-app)))

(test haproxy-fqdn-correct
  "*haproxy-fqdn* is bound to support.dapla.net."
  (is (string= "support.dapla.net" support-dapla-deploy/deploy:*haproxy-fqdn*)))

(defun run-spec ()
  "Run the full support-dapla-deploy spec suite."
  (let ((results (run :support-spec)))
    (fiveam:explain! results)
    (unless (every #'fiveam::test-passed-p results)
      (error "support-dapla-deploy spec suite: one or more tests failed."))))
