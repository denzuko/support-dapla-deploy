;;;; t/spec.lisp -- support-dapla-deploy/spec

(defpackage :support-dapla-deploy/spec
  (:use :cl :fiveam)
  (:import-from :support-dapla-deploy/deploy
                :stoat-network-sections
                :stoat-db-container-sections
                :stoat-cache-container-sections
                :stoat-files-container-sections
                :stoat-container-sections
                :haproxy-vhost-config
                :cinix-write-string)
  (:export :run-spec))

(in-package :support-dapla-deploy/spec)

(def-suite :quadlet-specifiers
  :description "Quadlet specifier correctness for support.dapla.net.")

(in-suite :quadlet-specifiers)

(defun ini-lines (ini)
  (remove-if (lambda (l) (zerop (length l)))
             (mapcar (lambda (l) (string-trim '(#\Space #\Return) l))
                     (uiop:split-string ini :separator '(#\Newline)))))

(defun ini-has (ini sub)
  (some (lambda (l) (search sub l)) (ini-lines ini)))

(test network-bridge
  "Network unit uses netavark bridge, not Internal=true."
  (let ((ini (cinix-write-string (stoat-network-sections))))
    (is (ini-has ini "Driver=bridge"))
    (is (not (ini-has ini "Internal=true")))))

(test network-vlsm
  "Network unit has correct VLSM subnet and gateway."
  (let ((ini (cinix-write-string (stoat-network-sections))))
    (is (ini-has ini "Subnet=10.89.2.36/29"))
    (is (ini-has ini "Gateway=10.89.2.37"))))

(test db-volume-srv
  "MongoDB data volume uses /srv/%U/db specifier."
  (is (ini-has (cinix-write-string (stoat-db-container-sections)) "Volume=/srv/%U/db")))

(test cache-volume-srv
  "KeyDB cache volume uses /srv/%U/cache specifier."
  (is (ini-has (cinix-write-string (stoat-cache-container-sections)) "Volume=/srv/%U/cache")))

(test files-volume-srv
  "Autumn files volume uses /srv/%U/files specifier."
  (is (ini-has (cinix-write-string (stoat-files-container-sections)) "Volume=/srv/%U/files")))

(test files-env-percent-h
  "Autumn EnvironmentFile uses %h/.env/secrets."
  (is (ini-has (cinix-write-string (stoat-files-container-sections)) "EnvironmentFile=%h")))

(test stoat-home-volume-ro
  "stoat.container has %h read-only home volume."
  (let* ((ini   (cinix-write-string (stoat-container-sections)))
         (lines (ini-lines ini))
         (vol   (find-if (lambda (l) (and (search "Volume=" l) (search "%h" l))) lines)))
    (is (not (null vol)))
    (when vol (is (search ":ro" vol)))))

(test stoat-config-volume-srv
  "stoat.container Revolt.toml comes from /srv/%U/config."
  (is (ini-has (cinix-write-string (stoat-container-sections)) "Volume=/srv/%U/config")))

(test stoat-no-publish-port
  "stoat.container has no PublishPort."
  (is (not (ini-has (cinix-write-string (stoat-container-sections)) "PublishPort"))))

(test haproxy-netavark-gateway
  "HAProxy backend uses netavark gateway 10.89.2.37, not loopback."
  (let ((cfg (haproxy-vhost-config)))
    (is (search "10.89.2.37" cfg))
    (is (not (search "127.0.0.1" cfg)))))

(defun run-spec ()
  (let ((results (run :quadlet-specifiers)))
    (fiveam:explain! results)
    (unless (every #'fiveam::test-passed-p results)
      (error "support-dapla-deploy spec suite: tests failed."))))
