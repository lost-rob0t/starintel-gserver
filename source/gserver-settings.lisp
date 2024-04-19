;; [[file:../source.org::*Settings][Settings:1]]
(in-package :star)
(defparameter *couchdb-host* "127.0.0.1" "The Couchdb host to use.")
(defparameter *couchdb-port* 5984 "The Couchdb port to use.")
(defparameter *couchdb-default-database* "starintel" "the default database name to use.")
(defparameter *couchdb-target-database* "starintel-targets" "the database to be used for target data.")
;; Settings:1 ends here

;; [[file:../source.org::*Listen Address][Listen Address:1]]
(defparameter *http-api-address* (or (uiop:getenv "HTTP_API_LISTEN_ADDRESS") "localhost") "the listen address")
(defparameter *http-api-port* 5000  "the port the api server listen on")
(defparameter *http-api-base-path* "/api" "the base url to use for the api endpoint")
(defparameter *http-cert-file* nil "path to the http api cert providing https")
(defparameter *http-key-file* nil "path to the http cert providing https")
(defparameter *http-scheme* 'http "use https or not.")
;; Listen Address:1 ends here

;; [[file:../source.org::*Authentication][Authentication:1]]
(defparameter *rabbit-address* (or (uiop:getenv "RABBITMQ_ADDRESS") "localhost") "The address rabbitmq is running on.")
(defparameter *rabbit-port* 5672 "The port that rabbitmq is listening on.")
(defparameter *rabbit-user* "guest" "the username for rabbimq")
(defparameter *rabbit-password* "guest" "the password for the rabbitmq user.")

(eval-when (:execute)
  )
;; Authentication:1 ends here
