(in-package :common-lisp)

(defclass foo ()
  ((x
    :initarg :x
    :accessor foo-x)
   (y)
   z)
  (:default-initargs :x 10))

(print (defgeneric hoge (x y)))
(print (defmethod hoge ((x integer) (y integer))
         (+ x y)))

(print (defmethod hoge ((x foo) y)
         (write-line "ok")
         (list x y)))

(print (hoge 1 2))

(print (make-instance 'foo))
(print (hoge (make-instance 'foo) 100))
