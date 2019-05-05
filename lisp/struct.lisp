(in-package :common-lisp)

(defmacro defstruct (name-and-options &rest slot-descriptions)
  (let ((name (if (consp name-and-options)
                  (first name-and-options)
                  name-and-options)))
    (check-type name symbol)
    (let ((constructor-name (intern (format nil "MAKE-~A" name))))
      `(progn
         (defun ,constructor-name (&key ,@(mapcar (lambda (slot-desc)
                                                    (if (consp slot-desc)
                                                        (list (first slot-desc)
                                                              (second slot-desc))
                                                        slot-desc))
                                           slot-descriptions))
           (system:make-structure ',name
                                  ,@(mapcar (lambda (slot-desc)
                                              (let ((slot-name
                                                      (if (consp slot-desc)
                                                          (first slot-desc)
                                                          slot-desc)))
                                                slot-name))
                                            slot-descriptions)))
         ,@(let ((i -1))
             (mapcar (lambda (slot-desc)
                       (let* ((slot-name (if (consp slot-desc)
                                             (first slot-desc)
                                             slot-desc))
                              (accessor (intern (format nil "~A-~A" name slot-name))))
                         (incf i)
                         `(defun ,accessor (structure)
                            (system:structure-index structure ,i))))
                     slot-descriptions))))))
