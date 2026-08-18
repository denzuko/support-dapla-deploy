;;;; chat-dapla-deploy.asd

(asdf:defsystem :chat-dapla-deploy)

(asdf:defsystem :chat-dapla-deploy/deploy
  :description "Roswell/Consfigurator deploy of Stoat (formerly Revolt) on
rootless Podman quadlets behind HAProxy at chat.dapla.net."
  :license "BSD-3-Clause"
  :depends-on (:cl-inix :consfigurator)
  :components ((:file "src/deploy"))
  :in-order-to ((asdf:test-op (asdf:test-op :chat-dapla-deploy/e2e))))

(asdf:defsystem :chat-dapla-deploy/docs
  :depends-on (:chat-dapla-deploy/deploy :40ants-doc :40ants-doc-full)
  :components ((:file "src/docs")))

(asdf:defsystem :chat-dapla-deploy/e2e
  :depends-on (:chat-dapla-deploy/deploy :fiveam :dexador)
  :components ((:file "t/e2e"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :fiveam :run! :chat-dapla-deploy-e2e)))
