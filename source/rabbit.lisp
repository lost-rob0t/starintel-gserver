(in-package :star.consumers)

(defvar +injest-queue+ "documents-injest")
(defvar +updates-queue+ "documents-updates")
(defvar +injest-key+ "documents.new.#")
(defvar +update-key+ "documents.update.#")
(defvar +targets-key+ "documents.new.target.*")

(defmacro with-rabbit-recv ((queue-name exchange-name exchange-type routing-key &key (port star:*rabbit-port*) (host star:*rabbit-address*) (username star:*rabbit-user*) (password star:*rabbit-password*) (vhost "/") (durable nil) (exclusive nil) (auto-delete nil)) &body body)
  `(cl-rabbit:with-connection (conn)
     (let ((socket (cl-rabbit:tcp-socket-new conn)))
       (cl-rabbit:socket-open socket ,host ,port)
       (when (and ,username ,password)
         (cl-rabbit:login-sasl-plain conn ,vhost ,username ,password))
       (cl-rabbit:with-channel (conn 1)
         (cl-rabbit:exchange-declare conn 1 ,exchange-name ,exchange-type)

         (cl-rabbit:queue-declare conn 1 :queue ,queue-name :durable ,durable :auto-delete ,auto-delete :exclusive ,exclusive)
         (cl-rabbit:queue-bind conn 1 :queue ,queue-name :exchange ,exchange-name :routing-key ,routing-key)

         (cl-rabbit:basic-consume conn 1 ,queue-name)
         (loop
           for result = (cl-rabbit:consume-message conn)
           for msg = (cl-rabbit:envelope/message result)
           do (handler-case (progn
                              ,@body
                              (cl-rabbit:basic-ack conn 1 (cl-rabbit:envelope/delivery-tag result)))
                (error (e) (cl-rabbit:basic-nack conn 1 (cl-rabbit:envelope/delivery-tag result) :requeue t))))))))

(defun emit-document (exchange routing-key body &key (properties nil)
                                                  (immediate nil)
                                                  (mandatory nil)
                                                  (port star:*rabbit-port*)
                                                  (host star:*rabbit-address*)
                                                  (username star:*rabbit-user*)
                                                  (password star:*rabbit-password*)
                                                  (vhost "/"))
  (cl-rabbit:with-connection (conn)
    (let ((socket (cl-rabbit:tcp-socket-new conn)))
      (cl-rabbit:socket-open socket host port)
      (when (and username password)
        (cl-rabbit:login-sasl-plain conn vhost username password))
      (cl-rabbit:with-channel (conn 1)
        (cl-rabbit:basic-publish conn 1 :routing-key routing-key :exchange exchange :mandatory mandatory :immediate immediate :properties properties :body body)))))

(defun message->string (msg &key (encoding :utf-8))
  "take a rabbitmq message and return the boddy as a string"
  (babel:octets-to-string (cl-rabbit:message/body msg) :encoding encoding))

                                        ;TODO
(defun message->object (msg)
  "Tale a rabbbitmq message and return a object. The object that will be returned depends on the message property 'dtype`.")

(defun handle-new-document (msg)
  "Handles any new incoming documents and sends it to the appropriate actors."
  (let* ((props (cl-rabbit:message/properties msg))
         (dtype (assoc :type props :test #'equal))
         (body (jsown:parse (message->string msg))))
    (cons (cdr dtype) body)))

;; [[file:../source.org::*Handle New Document consumers][Handle New Document consumers:2]]

(defun insert (client database document)
  (format nil "~a~%" (couch:create-document client database (jsown:to-json* document))))
;; (dex:http-request-conflict (e) (log:warn e))
;; (dex:http-request-unauthorized (e) (log:error e))



;; (defun start-rabbit-document-workers (n &key (port star:*rabbit-port*) (host star:*rabbit-address*) (username star:*rabbit-user*) (password star:*rabbit-password*))
;;   (loop for i from 0 below n
;;         do (bt:make-thread
;;             (lambda ()
;;               (let ((client (couch:new-couchdb star:*couchdb-host* star:*couchdb-port*))
;;                     (db star:*couchdb-default-database*))
;;                 (couch:password-auth client star:*couchdb-user* star:*couchdb-password*)
;;                 (handler-bind ((error #'(lambda (condition)
;;                                           (print condition))))
;;                   (with-rabbit-recv ("injest" "documents" "topic" "documents.new.#" :auto-delete nil :exclusive nil)
;;                     (let ((data (handle-new-document msg)))
;;                       (print (car data))
;;                       (handler-case (print (insert db (cdr data)))
;;                         (error (e) (print e)))
;;                       (force-output))))))

;;             ;; (sento-user::publish sento-user::*sys* (sento-user::new-event :topic (string-downcase (car data)) :data (cdr data)))

;;             :name "*new-documents*")))





(defclass consumer ()
  ((name :initarg :name :accessor consumer-name :initform "")
   (predicate :initarg :test-fn :initform (lambda (self message)
                                            (not (null message)))
              :accessor consumer-filter)
   (fn :initarg :fn :accessor consumer-fn :initform (lambda (self message)
                                                      (print message)) :type function)
   (take :initarg :take :accessor consumer-take :type integer :initform 1)
   (queue :initarg :state :accessor consumer-queue :type lparallel.queue:queue :initform (lparallel.queue:make-queue :fixed-capacity 100000))
   (worker-channel :initarg :consumer-channel :accessor consumer-channel :type lparallel:channel :initform (make-channel))
   (max-queue-size :initarg :max-size :accessor consumer-max-size :type integer)
   (state :initarg :state :accessor consumer-state)
   (consumer-stream :initarg :stream :reader consumer-stream)
   (lock :initform (bt:make-lock) :accessor consumer-lock))
  (:documentation "Consumers process a stream of data."))

(defgeneric consumer-state (consumer)
  (:documentation "Return the consumer's state"))

(defgeneric consumer-update-state (consumer new-state)
  (:documentation "Update the consumer state"))

(defgeneric consumer-cleanup (consumer)
  (:documentation "Close any streams and de-init the consumer"))

(defmacro with-consumer-lock ((consumer) &body body)
  `(bt:with-lock-held ((consumer-lock consumer))
     ,@body))

(defmethod consumer-update ((consumer consumer) new-state)
  (setf (consumer-state consumer) new-state))

(defmethod consumer-read ((consumer consumer))
  (stream-read (consumer-stream consumer)))

(defmethod consume  ((consumer consumer) data)
  (submit-task (consumer-channel consumer) (lambda ()
                                             (if (funcall (consumer-filter consumer) data)
                                                 (funcall (consumer-fn consumer) consumer data)))))




(defmethod start-consumer ((consumer consumer))
  (bt:make-thread (lambda ()
                    (loop
                      for data = (consumer-read consumer)
                      do (consume consumer data)
                      do (receive-result (consumer-channel consumer))))
                  :name (consumer-name consumer)))






(defun make-consumer (&rest args)
  (apply #'make-instance 'consumer args))




(defclass rabbit-queue-stream (cl-stream:sequence-input-stream)
  (
   (exchange :initform "amq.topic" :initarg :exchange-name :accessor rabbit-stream-exchange)
   (routing-key :initform "" :initarg :routing-key :accessor rabbit-stream-routing-key)
   (user :initform "" :initarg :user :accessor rabbit-stream-user)
   (password :initform "" :initarg :password :accessor rabbit-stream-password)
   (vhost :initform "/" :initarg :vhost :accessor rabbit-stream-vhost)
   (port :initform 5672 :initarg :vhost :accessor rabbit-stream-port)
   (host :initform "127.0.0.1" :initarg :host :accessor rabbit-stream-host)
   (queue-name :initarg :queue-name :accessor rabbit-stream-queue-name)
   (conn :initform nil :initarg :rabbit-connection :accessor rabbit-stream-connection)
   (chan :initform nil :initarg :rabbit-channel :accessor rabbit-stream-channel)
   (open :initform nil :accessor rabbit-stream-open-p))
  (:documentation "doc"))


(defmethod open-stream ((stream rabbit-queue-stream))
  (let* ((connection (cl-rabbit:new-connection))
         (sock (cl-rabbit:tcp-socket-new connection))
         (username (rabbit-stream-user stream))
         (password (rabbit-stream-password stream)))


    (setf (rabbit-stream-connection stream) connection)
    (cl-rabbit:socket-open sock (rabbit-stream-host stream) (rabbit-stream-port stream))
    (when (or username password)
      (cl-rabbit:login-sasl-plain connection (rabbit-stream-vhost stream) username password))
    (cl-rabbit:channel-open connection 1)
    (cl-rabbit:basic-qos connection 1 :prefetch-count 1)

    (cl-rabbit:queue-declare connection 1 :queue (rabbit-stream-queue-name stream))
    (cl-rabbit:queue-bind connection 1 :queue (rabbit-stream-queue-name stream) :exchange (rabbit-stream-exchange stream) :routing-key (rabbit-stream-routing-key stream))
    (cl-rabbit:basic-consume connection 1 (rabbit-stream-queue-name stream))
    (setf (rabbit-stream-open-p stream) t)))

()


(defmethod close-stream ((stream rabbit-queue-stream))
  (cl-rabbit:channel-close (rabbit-stream-connection stream) 1)
  (cl-rabbit:destroy-connection (rabbit-stream-connection stream))
  (setf (rabbit-stream-open-p stream) nil))


(defmethod stream-read ((stream rabbit-queue-stream))
  (let ((conn (rabbit-stream-connection stream)))

    (cl-rabbit:consume-message conn)))




(defclass rabbit-consumer (consumer)
  ()
  (:documentation "Custome consumer class for rabbitmq"))

(defmethod consumer-read ((consumer rabbit-consumer))
  (let ((msg (stream-read (consumer-stream consumer))))
    (cons (babel:octets-to-string (cl-rabbit:message/body (cl-rabbit:envelope/message msg)) :encoding :utf-8)
          (cl-rabbit:envelope/delivery-tag msg))))




(defun handle-document (self message)
  (let ((client (couch:new-couchdb "127.0.0.1" 5984))
        (connection (rabbit-stream-connection (consumer-stream self)))
        (document (car message))
        (msg-key (cdr message)))
    (progn
      (couch:password-auth client "admin" "password")
      (handler-case (couch:create-document client "starintel-gserver" document)
        (dex:http-request-conflict (e) nil))

      (cl-rabbit:basic-ack connection 1 msg-key))))



(defun transient-p (message)
  (jsown:val-safe (jsown:parse (car message)) "transient"))

(defun insertp (message)
  (null (transient-p message)))

(defun start-document-consumer (n &key (port star:*rabbit-port*) (host star:*rabbit-address*) (username star:*rabbit-user*) (password star:*rabbit-password*))
  (loop for i from 1 to n
        for stream = (make-instance 'rabbit-queue-stream :host host :port port :user username :password password :queue-name "injest" :exchange-name "documents" :routing-key +injest-key+)
        for consumer = (make-instance 'rabbit-consumer :name (format nil "~a-~a" "document-consumer" i) :stream stream :fn #'handle-document :test-fn #'insertp)
        do (open-stream stream)
        do (start-consumer consumer)))





;; Handle New Document consumers:2 ends here

;; [[file:../source.org::*Handle New Target consumers][Handle New Target consumers:1]]
(defun handle-new-target (msg)
  "Handles any new incoming documents and sends it to the appropriate actors."
  (let* ((props (cl-rabbit:message/properties msg))
         (body (message->string msg)))
    body))
;; Handle New Target consumers:1 ends here

(defun start-rabbit-targets-thread (&key (port star:*rabbit-port*) (host star:*rabbit-address*) (username star:*rabbit-user*) (password star:*rabbit-password*))
  (loop for i from 0 to 3
        do (bt:make-thread
            (lambda ()
              (with-rabbit-recv ("injest-targets" "documents" "topic" "documents.new.target.*" :auto-delete nil :exclusive nil)
                (let ((data (jsown:parse (handle-new-target msg))))
                  (sento-user::tell sento-user::*targets* (cons 1 data))))

              :name "*new-targets-consumer*"))))

(defun test-make-doc ( &optional (type 'spec:person))

  (with-output-to-string (str) (cl-json:encode-json (starintel:set-meta (make-instance type :id (uuid:print-bytes nil (uuid:make-v4-uuid)) :lname "doe" :fname "john") "starintel") str)))

(defun test-send (n &optional (type 'spec:person))
  (cl-rabbit:with-connection (conn)
    (let ((socket (cl-rabbit:tcp-socket-new conn)))
      (cl-rabbit:socket-open socket "localhost" 5672)
      (cl-rabbit:login-sasl-plain conn "/" "guest" "guest")
      (cl-rabbit:with-channel (conn 1)
        (loop for i from 0 to n
              do (cl-rabbit:basic-publish conn 1
                                          :exchange "documents"
                                          :routing-key "documents.new.person"
                                          :body (with-output-to-string (str) (cl-json:encode-json (starintel:set-meta (make-instance type :id (uuid:print-bytes nil (uuid:make-v4-uuid)) :lname  (format nil "~a-~a" "doe" i) :fname "john") "starintel") str))
                                          :properties '((:type . "person"))))))))
