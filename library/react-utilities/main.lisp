(ffi:require js:react "react")

(defmacro define-react-component (name (&rest keys) &body body)
  (let ((garg (gensym))
        (gargs (gensym)))
    `(ffi:define-function ,name (,garg &rest ,gargs)
       (let ,(mapcar (lambda (key)
                       `(,key (ffi:aget ,garg (ffi:cl->js ,(compiler::kebab-to-lower-camel-case (string key))))))
                     keys)
         ,@body))))

(defmacro with-state (bindings &body body)
  (let ((setters '()))
    `(let* ,(mapcan (lambda (b)
                      (destructuring-bind (var setter default) b
                        (let ((state-var (gensym (string var)))
                              (set-fn (gensym)))
                          (push (cons set-fn setter) setters)
                          `((,state-var (js:react.use-state ,default))
                            (,var (ffi:aget ,state-var 0))
                            (,set-fn (ffi:aget ,state-var 1))))))
                    bindings)
       (flet ,(mapcar (lambda (elt)
                        (destructuring-bind (set-fn . setter) elt
                          (let ((arg (gensym)))
                            `(,setter (,arg) (funcall ,set-fn ,arg)))))
                      setters)
         ,@body))))

(defmacro tag (tag option &body children)
  `(js:react.create-element ,(cond ((and (symbolp tag) (eq (find-package :js) (symbol-package tag)))
                                    `(ffi:cl->js ,tag))
                                   ((or (stringp tag) (symbolp tag))
                                    `(ffi:cl->js ,(string-downcase tag)))
                                   (t
                                    `(ffi:cl->js ,tag)))
                            (ffi:object . ,option)
                            ,@(mapcar (lambda (c) `(ffi:cl->js ,c))
                                      children)))

(defmacro jsx (form)
  (if (atom form)
      form
      (destructuring-bind (tag-name options &body body) form
        (cond ((keywordp tag-name)
               `(tag ,tag-name ,options
                     ,@(mapcar (lambda (form)
                                 `(jsx ,form))
                               body)))
              (t
               form)))))
