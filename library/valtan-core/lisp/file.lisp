(in-package :common-lisp)

#+node (ffi:require js:fs "fs")

(defun open (filename &key (direction :input) element-type if-exists if-does-not-exist)
  (declare (ignore element-type if-exists if-does-not-exist))
  (ecase direction
    (:input
     (make-file-input-stream
      :string-stream
      (make-string-input-stream
       (*:raw-string-to-array
        ((ffi:ref "fs" "readFileSync")
         (*:array-to-raw-string filename)
         (*:array-to-raw-string "utf-8"))))))
    ;(:output)
    ))

(defmacro with-open-file ((var filename &rest options
                                        &key (direction :input)
                                             element-type
                                             if-exists
                                             if-does-not-exist)
                          &body body)
  (declare (ignore direction element-type if-exists if-does-not-exist))
  `(with-open-stream (,var (open ,filename ,@options))
     ,@body))
