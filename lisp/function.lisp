(in-package :common-lisp)

(defun ensure-function (value)
  (cond ((functionp value)
         value)
        ((symbolp value)
         (symbol-function value))
        (t
         (type-error value 'function))))

(defun funcall (function &rest args)
  (let ((function (ensure-function function)))
    (system::apply function (system::list-to-js-array args))))

(defun apply (function arg &rest args)
  (let ((function (ensure-function function)))
    (cond ((null args)
           (unless (listp arg)
             (type-error arg 'list))
           (system::apply function (system::list-to-js-array arg)))
          (t
           (let* ((head (list arg))
                  (tail head))
             (do ((rest args (cdr rest)))
                 ((null (cdr rest))
                  (unless (listp (car rest))
                    (type-error (car rest) 'list))
                  (setf (cdr tail) (car rest)))
               (let ((a (car rest)))
                 (setf (cdr tail) (list a))
                 (setq tail (cdr tail))))
             (system::apply function (system::list-to-js-array head)))))))

(defun fdefinition (x) (symbol-function x))

(defun (setf fdefinition) (function x)
  (setf (symbol-function x) function))
