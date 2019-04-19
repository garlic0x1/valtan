(in-package :compiler)

(defparameter *pass1-form-table* (make-hash-table))

(defvar *lexenv*)

(defstruct binding
  name
  type
  value)

(defstruct parsed-lambda-list
  vars
  rest-var
  optionals)

(defmacro def-pass1-form (name lambda-list &body body)
  (let ((fn-name (intern (format nil "PASS1-~A" name))))
    `(progn
       (defun ,fn-name ,lambda-list ,@body)
       (setf (gethash ',name *pass1-form-table*) ',fn-name))))

(defun get-macro (symbol)
  (get symbol 'macro))

(defun set-macro (symbol form)
  (setf (get symbol 'macro) form))

(defun lookup (symbol type)
  (dolist (binding *lexenv*)
    (when (and (eq type (binding-type binding))
               (eq symbol (binding-name binding)))
      (return (binding-value binding)))))

(defun extend-lexenv (bindings lexenv)
  (append bindings lexenv))

(defun check-args (args min &optional (max min))
  (if max
      (assert (<= min (length args) max))
      (assert (<= min (length args)))))

(defun variable-symbol-p (x)
  (and (symbolp x)
       (not (null x))
       (not (keywordp x))))

(defun check-variable (x)
  (assert (variable-symbol-p x)))

(defun check-proper-list (x)
  (assert (and (listp x)
               (null (cdr (last x))))))

(defun check-lambda-list (lambda-list)
  (do ((x* lambda-list (rest x*)))
      ((null x*))
    (let ((x (first x*)))
      (assert (not (member x (rest x*))))
      (check-variable x))))

(defun check-lambda-form (form)
  (check-args (rest form) 1 nil)
  (check-lambda-list (second form)))

(defun check-duplicate-var (vars)
  (do ((var* vars (rest var*)))
      ((null var*))
    (when (member (first var*) (rest var*))
      (error "error"))))

(defun collect-variables (parsed-lambda-list)
  (append (parsed-lambda-list-vars parsed-lambda-list)
          (if (parsed-lambda-list-rest-var parsed-lambda-list)
              (list (parsed-lambda-list-rest-var parsed-lambda-list)))
          (if (parsed-lambda-list-optionals parsed-lambda-list)
              (mapcar #'first (parsed-lambda-list-optionals parsed-lambda-list)))))

(defun parse-lambda-list (lambda-list)
  (let ((vars '())
        (rest-var nil)
        (in-optional nil)
        (optionals '()))
    (do ((arg* lambda-list (cdr arg*)))
        ((null arg*))
      (let ((arg (car arg*)))
        (cond (rest-var
               (error "error"))
              ((eq arg '&rest)
               (unless (consp (cdr arg*))
                 (error "error"))
               (check-variable (second arg*))
               (setf rest-var (second arg*))
               (setq arg* (cdr arg*)))
              ((eq arg '&optional)
               (when in-optional
                 (error "error"))
               (setq in-optional t))
              (in-optional
               (cond ((symbolp arg)
                      (check-variable arg)
                      (push (list arg nil) optionals))
                     ((consp arg)
                      (check-proper-list arg)
                      (let ((len (length arg)))
                        (case len
                          ((1 2 3)
                           (when (= len 3)
                             (check-variable (third arg))
                             (when (eq (first arg) (third arg))
                               (error "error")))
                           (push (list (first arg)
                                       (second arg)
                                       (third arg))
                                 optionals))
                          (t
                           (error "error")))))
                     (t
                      (error "error"))))
              (t
               (push arg vars)))))
    (let ((parsed-lambda-list
            (make-parsed-lambda-list
             :vars (nreverse vars)
             :optionals (nreverse optionals)
             :rest-var rest-var)))
      (let ((all-vars (collect-variables parsed-lambda-list)))
        (check-duplicate-var all-vars))
      parsed-lambda-list)))

(defun get-transform (symbol)
  (get symbol 'transform))

(defun transform-symbol-p (symbol)
  (get-transform symbol))

(defmacro def-transform (name lambda-list &body body)
  `(setf (get ',name 'transform)
         (lambda ,lambda-list ,@body)))

(def-transform defun (name lambda-list &rest body)
  `(system::fset ',name (lambda ,lambda-list ,@body)))

(def-transform defmacro (name lambda-list &rest body)
  (set-macro name (eval `(lambda ,lambda-list ,@body)))
  `(system::add-global-macro ',name (lambda ,lambda-list ,@body)))

(def-transform lambda (args &rest body)
  `(function (lambda ,args ,@body)))

(defun expand-quasiquote (x)
  (cond ((atom x)
         (list 'quote x))
        ((eq 'system::unquote (first x))
         (check-args x 2)
         (second x))
        ((and (consp (first x))
              (eq (first (first x)) 'system::unquote-splicing))
         (check-args (first x) 2)
         (list 'append (second (first x)) (rest x)))
        (t
         (list 'cons
               (expand-quasiquote (first x))
               (expand-quasiquote (rest x))))))

(def-transform system::quasiquote (x)
  (expand-quasiquote x))

(defun pass1-const (x)
  (make-ir 'const x))

(defun pass1-refvar (symbol)
  (let ((var (lookup symbol :variable)))
    (if var
        (make-ir 'lref var)
        (make-ir 'gref symbol))))

(defun pass1-forms (forms)
  (mapcar #'pass1 forms))

(defun pass1-lambda (form)
  (unless (eq (first form) 'lambda)
    (error "error"))
  (check-args (rest form) 1 nil)
  (let ((parsed-lambda-list (parse-lambda-list (second form)))
        (body (cddr form)))
    (make-ir 'lambda
             parsed-lambda-list
             (let* ((symbols (collect-variables parsed-lambda-list))
                    (*lexenv*
                      (extend-lexenv (mapcar (lambda (symbol)
                                               (make-binding :name symbol
                                                             :type :variable
                                                             :value symbol))
                                             symbols)
                                     *lexenv*)))
               (pass1-forms body)))))

(defun %macroexpand-1 (form)
  (cond ((symbolp form)
         (values form nil))
        ((and (consp form) (symbolp (first form)))
         (let ((fn (get-macro (first form))))
           (if fn
               (values (apply fn (rest form)) t)
               (values form nil))))
        (t
         (values form nil))))

(defun pass1-call-symbol (symbol args)
  (if (transform-symbol-p symbol)
      (pass1 (apply (get-transform symbol) args))
      (make-ir 'call symbol (mapcar #'pass1 args))))

(defun lambda-to-let (form)
  ;; FIXME: lambda-listのシンボルと引数の数が合っているか確認していない
  (let ((lambda-form (first form)))
    `(let ,(mapcar #'list (second lambda-form) (rest form))
       ,@(rest (rest lambda-form)))))

(defun pass1-call (form)
  (let ((fn (first form))
        (args (rest form)))
    (cond ((symbolp fn)
           (pass1-call-symbol fn args))
          ((consp fn)
           (unless (eq 'lambda (first fn))
             (error "error"))
           (pass1 (list* 'funcall fn args)))
          (t
           (error "invalid form: ~S" form)))))

(defun pass1 (form)
  (multiple-value-bind (form expanded-p)
      (%macroexpand-1 form)
    (cond (expanded-p
           (pass1 form))
          ((null form)
           (pass1-const nil))
          ((symbolp form)
           (pass1-refvar form))
          ((atom form)
           (pass1-const form))
          (t
           (let ((fn (gethash (first form) *pass1-form-table*)))
             (if fn
                 (apply fn (rest form))
                 (pass1-call form)))))))

(def-pass1-form quote (x)
  (pass1-const x))

(def-pass1-form setq (&rest args)
  (if (not (evenp (length args)))
      (error "error")
      (let ((forms '()))
        (do ((args args (rest (rest args))))
            ((null args))
          (assert (symbolp (first args)))
          (let* ((symbol (first args))
                 (var (lookup symbol :variable))
                 (value (pass1 (second args))))
            (push (if var
                      (make-ir 'lset var value)
                      (make-ir 'gset symbol value))
                  forms)))
        (make-ir 'progn (nreverse forms)))))

(def-pass1-form if (test then &optional else)
  (make-ir 'if
           (pass1 test)
           (pass1 then)
           (pass1 else)))

(def-pass1-form progn (&rest forms)
  (make-ir 'progn (pass1-forms forms)))

(def-pass1-form function (thing)
  (cond
    ((eq (car thing) 'lambda)
     (pass1-lambda thing))
    (t
     (error "error"))))

(def-pass1-form let (bindings &rest body)
  (assert (consp bindings))
  (let ((bindings (mapcar (lambda (b)
                            (assert (consp b))
                            (assert (<= 1 (length b) 2))
                            (check-variable (first b))
                            (make-binding :name (first b) :value (first b) :type :variable))
                          bindings)))
    (make-ir 'let
             (mapcar #'list bindings 
             (let ((*lexenv* (extend-lexenv bindings *lexenv*)))
               (pass1-forms body)))))

(defun pass1-toplevel (form)
  (let ((*lexenv* '()))
    (make-ir 'progn (list (pass1 form)))))
