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
