;;;; t/e2e.lisp -- chat-dapla-deploy/e2e
;;;;
;;;; Post-deploy smoke tests for the Stoat stack. Run via
;;;; `./chat-dapla-deploy.ros e2e` against a live deployment.

(defpackage :chat-dapla-deploy/e2e
  (:use :cl :fiveam)
  (:import-from :chat-dapla-deploy/deploy :*haproxy-fqdn*)
  (:export :run-e2e))

(in-package :chat-dapla-deploy/e2e)

(def-suite :chat-dapla-deploy-e2e
  :description "Smoke tests for Stoat at chat.dapla.net.")

(in-suite :chat-dapla-deploy-e2e)

(defun base-url ()
  (format nil "https://~A" *haproxy-fqdn*))

(test http-redirect
  "Plain HTTP requests redirect to HTTPS."
  (multiple-value-bind (body status)
      (dex:get (format nil "http://~A/" *haproxy-fqdn*)
               :force-string t :want-stream nil :redirect nil)
    (declare (ignore body))
    (is (member status '(301 302)))))

(test api-responds
  "The Stoat API returns HTTP 200 at the root."
  (multiple-value-bind (body status)
      (dex:get (base-url) :force-string t :want-stream nil)
    (declare (ignore body))
    (is (= 200 status))))

(test api-version-endpoint
  "The /api/version endpoint returns JSON with a version field."
  (multiple-value-bind (body status)
      (dex:get (format nil "~A/api/version" (base-url))
               :force-string t :want-stream nil)
    (is (= 200 status))
    (is (search "revolt" body))))

(test file-server-responds
  "The file server health endpoint returns HTTP 200."
  (multiple-value-bind (body status)
      (dex:get (format nil "~A/api/autumn" (base-url))
               :force-string t :want-stream nil)
    (declare (ignore body))
    (is (= 200 status))))

(defun run-e2e ()
  "Run the post-deploy e2e suite and signal an error if any test fails."
  (let ((results (run :chat-dapla-deploy-e2e)))
    (unless (every #'fiveam::test-passed-p results)
      (error "chat-dapla-deploy e2e suite: one or more tests failed."))))
