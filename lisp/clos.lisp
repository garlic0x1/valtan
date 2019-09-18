(in-package :common-lisp)

(defvar +standard-class+)

(defstruct (standard-object (:print-function print-standard-object))
  class
  slots)

(defstruct slot-definition
  name
  initargs
  initform
  initfunction
  readers
  writers
  allocation)

(defun print-standard-object (standard-object stream depth)
  (declare (ignore depth))
  (print-unreadable-object (standard-object stream)
    (format stream "~S ~S"
            (class-name (standard-object-class standard-object))
            (class-name standard-object))))

(defun %slot-value (class slot-name)
  (let ((elt (assoc slot-name (standard-object-slots class))))
    (unless elt
      (error "The slot ~S is unbound in the object ~S."
             slot-name class))
    (cdr elt)))

(defun (setf %slot-value) (value class slot-name)
  (let ((elt (assoc slot-name (standard-object-slots class))))
    (if elt
        (setf (cdr elt) value)
        (push (cons slot-name value) (standard-object-slots class)))
    value))

(defun class-name (class)
  (%slot-value class 'name))

(defun (setf class-name) (name class)
  (setf (%slot-value class 'name) name))

(defun class-of (x)
  (if (standard-object-p x)
      (standard-object-class x)
      (error "trap")))

(let ((class-table (make-hash-table)))
  (defun find-class (symbol &optional (errorp t) environment)
    (declare (ignore environment))
    (let ((class (gethash symbol class-table)))
      (when (and (null class) errorp)
        (error "There is no class named ~S." symbol))
      class))

  (defun (setf find-class) (class symbol &optional errorp environment)
    (declare (ignore errorp environment))
    (setf (gethash symbol class-table) class)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun canonicalize-direct-slot (direct-slot-spec)
    (let ((result `(:name ,(if (consp direct-slot-spec)
                               (car direct-slot-spec)
                               direct-slot-spec)))
          (others '()))
      (do ((plist (if (consp direct-slot-spec) (cdr direct-slot-spec) nil)
                  (cddr plist)))
          ((null plist))
        (let ((key (car plist))
              (value (cadr plist)))
          (case key
            (:initform
             (setq result
                   (append result `(:initform ,value
                                    :initfunction (lambda () ,value)))))
            (:initarg
             (setf (getf result :initargs)
                   (nconc (getf result :initargs)
                          (list value))))
            ((:reader :writer :accessor)
             (case key
               ((:accessor :reader)
                (setf (getf result :readers)
                      (nconc (getf result :readers)
                             (list value)))))
             (case key
               (:writer
                (setf (getf result :writers)
                      (nconc (getf result :writers)
                             (list value))))
               (:accessor
                (setf (getf result :writers)
                      (nconc (getf result :writers)
                             (list `(setf ,value)))))))
            (:documentation
             (setf (getf result :documentation) value))
            (otherwise
             (setf (getf others key)
                   (nconc (getf others key) (list value)))))))
      (do ((plist others (cddr plist)))
          ((null plist))
        (let ((k (car plist))
              (v (cadr plist)))
          (setf (getf result k)
                (if (null (cdr v))
                    (car v)
                    v))))
      (do ((plist result (cddr plist)))
          ((null plist))
        (setf (car plist) `(quote ,(car plist)))
        (setf (cadr plist) `(quote ,(cadr plist))))
      `(list ,@result)))

  (defun canonicalize-direct-slot-specs (direct-slot-specs)
    `(list ,@(mapcar #'canonicalize-direct-slot direct-slot-specs)))

  (defun canonicalize-defclass-options (options)
    (mapcan (lambda (elt)
              (let ((key (car elt))
                    (rest (cdr elt)))
                (when (eq key :default-initargs)
                  (setq key :direct-default-initargs))
                (list key
                      (case key
                        (:direct-default-initargs
                         (let ((initargs '()))
                           (do ((plist rest (cddr plist)))
                               ((null plist))
                             (push `(list ,(car plist)
                                          ,(cadr plist)
                                          (lambda () ,(cadr plist)))
                                   initargs))
                           `(list ,@(nreverse initargs))))
                        ((:metaclass :documentation)
                         `(quote ,(car rest)))
                        (otherwise
                         `(quote ,rest))))))
            options)))

(defun canonicalize-class (class &optional (errorp t))
  (if (symbolp class) (find-class class errorp) class))

(defun check-duplicate-direct-slots (direct-slots)
  (flet ((name (direct-slot) (getf direct-slot :name)))
    (do ((direct-slots direct-slots (cdr direct-slots)))
        ((null direct-slots))
      (let ((direct-slot (car direct-slots)))
        (when (member (name direct-slot)
                      (cdr direct-slots)
                      :key #'name)
          (error "Duplicate slot ~S" (name direct-slot)))))))

(defun check-duplicate-direct-default-initargs (direct-default-initargs class-name)
  (do ((direct-default-initargs direct-default-initargs (cdr direct-default-initargs)))
      ((null direct-default-initargs))
    (when (member (caar direct-default-initargs) (cdr direct-default-initargs) :key #'car)
      (error "Duplicate initialization argument name ~S in :DEFAULT-INITARGS DEFCLASS ~S."
             (caar direct-default-initargs)
             class-name))))

(defmacro defclass (name direct-superclasses direct-slot-specs &rest options)
  `(ensure-class ',name
                 :direct-superclasses ',direct-superclasses
                 :direct-slots ,(canonicalize-direct-slot-specs direct-slot-specs)
                 ,@(canonicalize-defclass-options options)))

(defun ensure-class (name &rest args)
  (apply #'ensure-class-using-class (find-class name nil) name args))

(defun ensure-class-using-class (class name &key direct-default-initargs direct-slots
                                                 direct-superclasses #|name|#
                                                 (metaclass 'standard-class)
                                            &allow-other-keys)
  (check-duplicate-direct-slots direct-slots)
  (check-duplicate-direct-default-initargs direct-default-initargs name)
  (cond (class
         (error "trap"))
        (t
         (setq metaclass (canonicalize-class metaclass))
         (setf (find-class name)
               (apply (if (eq metaclass +standard-class+)
                          #'make-instance-standard-class
                          (error "make-instance trap"))
                      metaclass
                      :name name
                      :direct-default-initargs direct-default-initargs
                      :direct-slots direct-slots
                      :direct-superclasses direct-superclasses)))))

(defun make-instance-standard-class (metaclass &key name
                                                    direct-superclasses
                                                    direct-slots
                                                    direct-default-initargs
                                               &allow-other-keys)
  ;(assert (eq metaclass +standard-class+))
  (let ((class (allocate-instance metaclass)))
    (setf (class-name class) name)
    (setf (class-direct-subclasses class) '())
    (setf (class-direct-methods class) '())
    (setf (class-direct-default-initargs class) direct-default-initargs)
    (std-after-initialization-for-classes
     class
     :direct-slots direct-slots
     :direct-default-initargs direct-default-initargs)
    class))

(defun std-after-initialization-for-classes (class &key direct-superclasses
                                                        direct-slots
                                                   &allow-other-keys)
  (let ((supers (or direct-superclasses (list (find-class 'standard-object)))))
    (setf (class-direct-superclasses class) supers)
    (dolist (superclass supers)
      (push class (class-direct-subclasses superclass))))
  (let ((slots
          (mapcar (lambda (slot-plist)
                    (apply #'make-direct-slot-definition slot-plist))
                  direct-slots)))
    (class-direct-slots class) slots)
  (dolist (direct-slot slots)
    (dolist (reader (slot-definition-readers direct-slot))
      (add-reader-method class reader (slot-definition-name direct-slot)))
    (dolist (writer (slot-definition-writers direct-slot))
      (add-writer-method class writer (slot-definition-name direct-slot))))
  (if (eq (class-of class) +standard-class+)
      (std-finalize-inheritance class)
      (error "finalize-inheritance trap")))

(defun make-direct-slot-definition (&rest args
                                    &key name initargs initform initfunction readers writers
                                         (allocation :instance)
                                    &allow-other-keys)
  (declare (ignore name initargs initform initfunction readers writers allocation))
  (apply #'make-slot-definition args))

(defun make-effective-slot-definition (&rest args
                                       &key name initargs initform initfunction
                                            (allocation :instance)
                                       &allow-other-keys)
  (declare (ignore name initargs initform initfunction allocation))
  (apply #'make-slot-definition args))

(defun allocate-instance (class)
  (make-standard-object :class class))

(defun initialize-instance (instance &rest initargs)
  )

(defun make-instance (class &rest initargs)
  (setq class (canonicalize-class class))
  (let ((instance (allocate-instance class)))
    (apply #'initialize-instance instance initargs)
    instance))

(defun add-reader-method (class fn-name slot-name)
  )

(defun add-writer-method (class fn-name slot-name)
  )

(setq +standard-class+
      (let ((standard-class (make-standard-object)))
        (setf (standard-object-class standard-class) standard-class)
        (setf (class-name standard-class) 'standard-class)
        standard-class))

(setf (find-class 'standard-class) +standard-class+)
