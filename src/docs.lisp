;;;; src/docs.lisp -- support-dapla-deploy/docs
;;;;
;;;; 40ants-doc sections for the support-dapla-deploy system.

(defpackage :support-dapla-deploy/docs
  (:use :cl)
  (:import-from :40ants-doc :defsection))

(in-package :support-dapla-deploy/docs)

(defsection @support-dapla-deploy (:title "support-dapla-deploy")
  "Roswell/Consfigurator deploy of Stoat at support.dapla.net."
  (@deploy-properties section)
  (@quadlet-builders section))

(defsection @deploy-properties (:title "Consfigurator Properties")
  (support-dapla-deploy/deploy:zfs-encryption-key        function)
  (support-dapla-deploy/deploy:zfs-dataset-mounted       function)
  (support-dapla-deploy/deploy:rootless-service-account  function)
  (support-dapla-deploy/deploy:images-pulled             function)
  (support-dapla-deploy/deploy:quadlets-activated        function)
  (support-dapla-deploy/deploy:deploy-app                function))

(defsection @quadlet-builders (:title "Quadlet Unit Builders")
  (support-dapla-deploy/deploy:cinix-write-string             function)
  (support-dapla-deploy/deploy:invidious-network-sections     function)
  (support-dapla-deploy/deploy:invidious-db-container-sections function)
  (support-dapla-deploy/deploy:invidious-container-sections   function)
  (support-dapla-deploy/deploy:haproxy-vhost-config           function))
