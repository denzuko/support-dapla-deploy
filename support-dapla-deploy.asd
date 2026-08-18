;;;; support-dapla-deploy.asd

(asdf:defsystem :support-dapla-deploy)

(asdf:defsystem :support-dapla-deploy/deploy
  :description "Roswell/Consfigurator deploy of Stoat (formerly Revolt) on
rootless Podman quadlets behind HAProxy at support.dapla.net."
  :license "BSD-3-Clause"
  :depends-on (:cl-inix :consfigurator)
  :components ((:file "src/deploy"))
  :in-order-to ((asdf:test-op (asdf:test-op :support-dapla-deploy/e2e))))

(asdf:defsystem :support-dapla-deploy/docs
  :depends-on (:support-dapla-deploy/deploy :40ants-doc :40ants-doc-full)
  :components ((:file "src/docs")))

(asdf:defsystem :support-dapla-deploy/e2e
  :depends-on (:support-dapla-deploy/deploy :fiveam :dexador)
  :components ((:file "t/e2e"))
  :perform (asdf:test-op (op c)
             (uiop:symbol-call :fiveam :run! :support-dapla-deploy-e2e)))
