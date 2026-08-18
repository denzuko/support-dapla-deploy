;;;; src/docs.lisp -- support-dapla-deploy/docs
;;;;
;;;; Loaded as the :SUPPORT-DAPLA-DEPLOY/DOCS ASDF system, separate from
;;;; the core deploy system so a production binary never pulls in 40ants-doc.

(defpackage :support-dapla-deploy/docs
  (:use :cl)
  (:import-from :40ants-doc :defsection))

(in-package :support-dapla-deploy/docs)

(defsection @support-dapla-deploy (:title "support-dapla-deploy")
  "Roswell/Consfigurator deploy of Stoat at support.dapla.net."
  (@deploy-properties section)
  (@quadlet-builders section))


(defsection @network-allocation (:title "Network Allocation")
  "The support.dapla.net service runs on netavark bridge network
   podman10 (10.89.2.36/29), gateway 10.89.2.37.

   Full dapla.net VLSM allocation (10.89.2.0/26):

   | Service | Network  | Subnet         | Gateway     | /  | Containers |
   |---------|----------|----------------|-------------|-----|-----------|
   | find    | podman3  | 10.89.2.0/30   | 10.89.2.1   | 30 | 1         |
   | watch   | podman4  | 10.89.2.4/29   | 10.89.2.5   | 29 | 2         |
   | meet    | podman5  | 10.89.2.12/29  | 10.89.2.13  | 29 | 3         |
   | feed    | podman6  | 10.89.2.20/30  | 10.89.2.21  | 30 | 1         |
   | save    | podman7  | 10.89.2.24/30  | 10.89.2.25  | 30 | 1         |
   | burn    | podman8  | 10.89.2.28/30  | 10.89.2.29  | 30 | 1         |
   | link    | podman9  | 10.89.2.32/30  | 10.89.2.33  | 30 | 1         |
   | support | podman10 | 10.89.2.36/29  | 10.89.2.37  | 29 | 4         |

   Existing host networks: podman1=10.89.0.0/24, podman2=10.89.1.0/24.
   HAProxy backend -> gateway IP:internal port. No loopback, no port arithmetic.")

(defsection @deploy-properties (:title "Consfigurator Properties")
  (support-dapla-deploy/deploy:zfs-encryption-key       function)
  (support-dapla-deploy/deploy:zfs-dataset-mounted      function)
  (support-dapla-deploy/deploy:rootless-service-account function)
  (support-dapla-deploy/deploy:images-pulled            function)
  (support-dapla-deploy/deploy:quadlets-written         function)
  (support-dapla-deploy/deploy:haproxy-vhost-written    function)
  (support-dapla-deploy/deploy:quadlets-activated       function)
  (support-dapla-deploy/deploy:deploy-app               function))

(defsection @quadlet-builders (:title "Quadlet Unit Builders")
  (support-dapla-deploy/deploy:cinix-write-string              function)
  (support-dapla-deploy/deploy:service-account-uid             function)
  (support-dapla-deploy/deploy:stoat-network-sections          function)
  (support-dapla-deploy/deploy:stoat-db-container-sections     function)
  (support-dapla-deploy/deploy:stoat-cache-container-sections  function)
  (support-dapla-deploy/deploy:stoat-files-container-sections  function)
  (support-dapla-deploy/deploy:stoat-container-sections        function)
  (support-dapla-deploy/deploy:haproxy-vhost-config            function))
