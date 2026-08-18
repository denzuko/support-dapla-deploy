;;;; src/docs.lisp -- chat-dapla-deploy/docs
;;;;
;;;; 40ants-doc sections for the chat-dapla-deploy system.

(defpackage :chat-dapla-deploy/docs
  (:use :cl)
  (:import-from :40ants-doc :defsection))

(in-package :chat-dapla-deploy/docs)

(defsection @chat-dapla-deploy (:title "chat-dapla-deploy")
  "Roswell/Consfigurator deploy of Stoat at chat.dapla.net."
  (@deploy-properties section)
  (@quadlet-builders section))

(defsection @deploy-properties (:title "Consfigurator Properties")
  (chat-dapla-deploy/deploy:zfs-encryption-key        function)
  (chat-dapla-deploy/deploy:zfs-dataset-mounted       function)
  (chat-dapla-deploy/deploy:rootless-service-account  function)
  (chat-dapla-deploy/deploy:images-pulled             function)
  (chat-dapla-deploy/deploy:quadlets-activated        function)
  (chat-dapla-deploy/deploy:deploy-app                function))

(defsection @quadlet-builders (:title "Quadlet Unit Builders")
  (chat-dapla-deploy/deploy:cinix-write-string             function)
  (chat-dapla-deploy/deploy:invidious-network-sections     function)
  (chat-dapla-deploy/deploy:invidious-db-container-sections function)
  (chat-dapla-deploy/deploy:invidious-container-sections   function)
  (chat-dapla-deploy/deploy:haproxy-vhost-config           function))
