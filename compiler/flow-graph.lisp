(in-package :compiler)

(defparameter +start-node-name+ (make-symbol "START"))

(defstruct compiland
  vars
  functions
  start-basic-block
  basic-blocks)

(defstruct basic-block
  id
  code
  succ
  pred)

(defstruct (while-block (:include basic-block))
  exit)

(defun check-basic-block-succ-pred (bb)
  (mapc (lambda (pred)
          (let ((count (count (basic-block-id bb)
                              (mapcar #'basic-block-id (basic-block-succ pred))
                              :test #'equal)))
            (assert (= 1 count))))
        (basic-block-pred bb))
  (mapc (lambda (succ)
          (let ((count (count (basic-block-id bb)
                              (mapcar #'basic-block-id (basic-block-pred succ))
                              :test #'equal)))
            (assert (= 1 count))))
          (basic-block-succ bb)))

(defun show-basic-block (bb)
  (format t "~A ~A~%" (basic-block-id bb) (mapcar #'basic-block-id (basic-block-pred bb)))
  (do-vector (lir (basic-block-code bb))
    (format t "  ~A~%" lir))
  (let ((succ (basic-block-succ bb)))
    (format t " ~A~%" (mapcar #'basic-block-id succ)))
  (handler-case (check-basic-block-succ-pred bb)
    (error ()
      (format t "ERROR~%"))))

(defun show-basic-blocks (compiland)
  (show-basic-block (compiland-start-basic-block compiland))
  (mapc #'show-basic-block (compiland-basic-blocks compiland))
  (values))

(defun create-compiland (hir)
  (multiple-value-bind (code vars functions)
      (hir-to-lir hir)
    (multiple-value-bind (basic-blocks start-basic-block)
        (split-basic-blocks code)
      (make-compiland :vars vars
                      :functions functions
                      :basic-blocks basic-blocks
                      :start-basic-block start-basic-block))))

(defun split-basic-blocks (code)
  (let ((current-block '())
        (basic-blocks '())
        (basic-block-counter 0))
    (flet ((add-block ()
             (unless (null current-block)
               (let ((code (coerce (nreverse current-block) 'vector)))
                 (push (make-basic-block :id (prog1 basic-block-counter
                                               (incf basic-block-counter))
                                         :code code
                                         :succ nil)
                       basic-blocks)))))
      (do-vector (lir code)
        (case (lir-op lir)
          ((label)
           (add-block)
           (setq current-block (list lir)))
          ((jump fjump)
           (push lir current-block)
           (add-block)
           (setf current-block '()))
          (otherwise
           (push lir current-block))))
      (add-block)
      (let (prev)
        (dolist (bb basic-blocks)
          (let ((last (vector-last (basic-block-code bb))))
            (case (lir-op last)
              ((jump fjump)
               (let* ((jump-label (lir-jump-label last))
                      (to (find-if (lambda (bb2)
                                     (let ((lir (vector-first (basic-block-code bb2))))
                                       (and (eq (lir-op lir) 'label)
                                            (eq (lir-arg1 lir) jump-label))))
                                   basic-blocks)))
                 (setf (basic-block-succ bb)
                       (let ((succ '()))
                         (when to
                           (push bb (basic-block-pred to))
                           (push to succ))
                         (when (and prev (eq (lir-op last) 'fjump))
                           (push bb (basic-block-pred prev))
                           (push prev succ))
                         succ))))
              (otherwise
               (when prev
                 (push bb (basic-block-pred prev))
                 (setf (basic-block-succ bb)
                       (list prev))))))
          (setf prev bb)))
      (let ((basic-blocks (nreverse basic-blocks))
            (start-basic-block (make-basic-block :id +start-node-name+)))
        (setf (basic-block-succ start-basic-block) (list (first basic-blocks)))
        (push start-basic-block (basic-block-pred (first basic-blocks)))
        (values basic-blocks start-basic-block)))))

(defun flatten-basic-blocks (compiland)
  (coerce (mapcan (lambda (bb)
                    (coerce (basic-block-code bb) 'list))
                  (compiland-basic-blocks compiland))
          'vector))

(defun remove-basic-block (bb)
  (dolist (pred (basic-block-pred bb))
    (setf (basic-block-succ pred)
          (mapcan (lambda (succ)
                    (if (eq succ bb)
                        (basic-block-succ bb)
                        (list succ)))
                  (basic-block-succ pred))))
  (dolist (succ (basic-block-succ bb))
    (setf (basic-block-pred succ)
          (mapcan (lambda (pred)
                    (if (eq pred bb)
                        (basic-block-pred bb)
                        (list pred)))
                  (basic-block-pred succ))))
  (values))

(defun remove-unused-block (compiland)
  (setf (compiland-basic-blocks compiland)
        (delete-if (lambda (bb)
                     (when (null (basic-block-pred bb))
                       (remove-basic-block bb)
                       t))
                   (compiland-basic-blocks compiland)))
  (values))

(defun remove-unused-label (compiland)
  (let ((label-table '())
        (basic-blocks (compiland-basic-blocks compiland)))
    (dolist (bb basic-blocks)
      (let* ((code (basic-block-code bb))
             (lir (vector-last code)))
        (when (lir-jump-p lir)
          (pushnew (lir-jump-label lir) label-table))))
    (setf (compiland-basic-blocks compiland)
          (delete-if (lambda (bb)
                       (let* ((code (basic-block-code bb))
                              (lir (aref code 0)))
                         (when (and (eq (lir-op lir) 'label)
                                    (not (member (lir-arg1 lir) label-table)))
                           (cond ((= 1 (length code))
                                  (remove-basic-block bb)
                                  t)
                                 (t
                                  (setf (basic-block-code bb)
                                        (subseq code 1))
                                  nil)))))
                     basic-blocks))
    (values)))

(defun merge-basic-block (bb1 bb2)
  (setf (basic-block-succ bb1)
        (basic-block-succ bb2))
  (assert (length=1 (basic-block-succ bb2)))
  (setf (basic-block-pred (first (basic-block-succ bb2)))
        (mapcar (lambda (pred)
                  (if (eq pred bb2)
                      bb1
                      pred))
                (basic-block-pred (first (basic-block-succ bb2)))))
  (setf (basic-block-code bb1)
        (concatenate 'vector
                     (basic-block-code bb1)
                     (basic-block-code bb2)))
  (values))

(defun merge-basic-blocks-1 (basic-blocks)
  (dolist (bb basic-blocks (values basic-blocks nil))
    (let ((code (basic-block-code bb))
          succ)
      (when (and (or (zerop (length code))
                     (not (lir-jump-p (vector-last code))))
                 (length=1 (basic-block-succ bb))
                 (setq succ (first (basic-block-succ bb)))
                 (not (eq succ bb))
                 (length=1 (basic-block-succ succ)))
        (merge-basic-block bb succ)
        (setf basic-blocks (delete succ basic-blocks))
        (return (values basic-blocks t))))))

(defun merge-basic-blocks (compiland)
  (let ((basic-blocks (compiland-basic-blocks compiland)))
    (do ((success t))
        ((not success))
      (setf (values basic-blocks success)
            (merge-basic-blocks-1 basic-blocks)))
    (setf (compiland-basic-blocks compiland) basic-blocks)
    (values)))

(defun create-dominator-table (compiland)
  (let ((d-table (make-hash-table))
        (all-nodes (cons (compiland-start-basic-block compiland)
                         (compiland-basic-blocks compiland))))
    (dolist (bb all-nodes)
      (setf (gethash (basic-block-id bb) d-table)
            (mapcar #'basic-block-id all-nodes)))
    (dolist (bb all-nodes)
      (let ((pred (basic-block-pred bb))
            (self-id (basic-block-id bb)))
        (if (null pred)
            (setf (gethash self-id d-table)
                  (list self-id))
            (let ((set (gethash (basic-block-id (first pred)) d-table)))
              (dolist (p (rest pred))
                (setq set (intersection set (gethash (basic-block-id p) d-table))))
              (setf (gethash self-id d-table)
                    (adjoin self-id set))))))
    (hash-table-to-alist d-table)))

(defun create-dominator-tree (d-table)
  (flet ((finish-p ()
           (dolist (elt d-table t)
             (and elt
                  (destructuring-bind (n . dominators) elt
                    (declare (ignore n))
                    (when (length>1 dominators)
                      (return nil)))))))
    (setq d-table (delete +start-node-name+ d-table :key #'car))
    (dolist (elt d-table)
      (destructuring-bind (n . dominators) elt
        (setf (cdr elt) (delete n dominators :count 1))))
    (do ()
        ((finish-p))
      (let ((idoms '()))
        (dolist (elt d-table)
          (destructuring-bind (n . dominators) elt
            (declare (ignore n))
            (when (length=1 dominators)
              (push (car dominators) idoms))))
        (dolist (elt d-table)
          (destructuring-bind (n . dominators) elt
            (declare (ignore n))
            (unless (length=1 dominators)
              (setf (cdr elt) (set-difference dominators idoms))))))))
  d-table)

(defun create-loop-graph (compiland d-table)
  (let ((visited (make-hash-table))
        (loop-graph '()))
    (labels ((f (bb)
               (unless (gethash (basic-block-id bb) visited)
                 (setf (gethash (basic-block-id bb) visited) t)
                 (dolist (s (basic-block-succ bb))
                   (if (and (gethash (basic-block-id s) visited)
                            (member (basic-block-id s)
                                    (cdr (assoc (basic-block-id bb) d-table))))
                       (push (list (basic-block-id s)
                                   (basic-block-id bb))
                             loop-graph))
                   (f s)))))
      (f (compiland-start-basic-block compiland))
      loop-graph)))

(defun map-basic-block (function start)
  (let ((visited (make-hash-table)))
    (labels ((f (bb)
               (unless (gethash (basic-block-id bb) visited)
                 (setf (gethash (basic-block-id bb) visited) t)
                 (funcall function bb)
                 (dolist (s (basic-block-succ bb))
                   (f s)))))
      (f (basic-block-succ start)))))

(defun structural-analysis (compiland)
  (let* ((d-table (create-dominator-table compiland))
         (loop-graph (create-loop-graph compiland d-table))
         (d-tree (create-dominator-tree d-table)))
    (declare (ignorable d-table loop-graph d-tree))
    (labels ((while-footer-p (bb header/footer)
               (and (length=1 (basic-block-succ bb))
                    (eql (basic-block-id bb)
                         (second header/footer))
                    (eql (basic-block-id (first (basic-block-succ bb)))
                         (first header/footer))))
             (while-header-p (bb)
               (let ((header/footer (assoc (basic-block-id bb) loop-graph))
                     (succ (basic-block-succ bb)))
                 (when (and header/footer
                            (length=n succ 2)
                            (< 0 (length (basic-block-code bb)))
                            (eq 'fjump (lir-op (vector-last (basic-block-code bb)))))
                   (multiple-value-bind (while-header-block while-footer-block break-block)
                       (cond ((while-footer-p (second succ) header/footer)
                              (values bb (second succ) (first succ)))
                             ((while-footer-p (first succ) header/footer)
                              (values bb (first succ) (second succ))))
                     (let ((code (basic-block-code while-footer-block)))
                       (and (< 0 (length code))
                            (eq 'label (lir-op (vector-first code)))
                            (eql (lir-arg1 (vector-first code))
                                 (lir-arg2 (vector-last (basic-block-code bb))))
                            (values while-header-block while-footer-block break-block)))))))
             (replace-to-while-block (while-header-block while-footer-block break-block)
               (let* ((header-code (basic-block-code while-header-block))
                      (footer-code (basic-block-code while-footer-block)))
                 (setf (vector-last header-code)
                       (make-lir 'break))
                 (setf (vector-first footer-code)
                       (make-lir 'nop))
                 (make-while-block :id (basic-block-id while-header-block)
                                   :pred (delete while-footer-block
                                                 (basic-block-succ while-header-block))
                                   :succ (delete while-footer-block
                                                 (basic-block-succ while-header-block))
                                   :exit break-block
                                   :code (concatenate 'vector
                                                      header-code
                                                      (basic-block-code while-footer-block))))))
      (let ((deleting-blocks '()))
        (do ((bb* (compiland-basic-blocks compiland) (cdr bb*)))
            ((null bb*))
          (let ((bb (car bb*)))
            (multiple-value-bind (while-header-block while-footer-block break-block)
                (while-header-p bb)
              (when while-header-block
                (push while-footer-block deleting-blocks)
                (setf (car bb*)
                      (replace-to-while-block while-header-block
                                              while-footer-block
                                              break-block))))))
        (dolist (bb deleting-blocks)
          (setf (compiland-basic-blocks compiland)
                (delete bb (compiland-basic-blocks compiland))))))))

(defun graphviz-compiland (compiland &optional (name "valtan") (open-viewer-p t))
  (let ((dot-filename (format nil "/tmp/~A.dot" name))
        (img-filename (format nil "/tmp/~A.png" name)))
    (with-open-file (out dot-filename
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (let ((basic-blocks (cons (compiland-start-basic-block compiland)
                                (compiland-basic-blocks compiland))))
        (write-line "digraph graph_name {" out)
        (write-line "graph [ labeljust = l; ]" out)
        (write-line "node [ shape = box; ]" out)
        (dolist (bb basic-blocks)
          (format out "~A [label = \"~A\\l" (basic-block-id bb) (basic-block-id bb))
          (do-vector (lir (basic-block-code bb))
            (write-string (princ-to-string (cons (lir-op lir) (lir-args lir))) out)
            (write-string "\\l" out))
          (format out "\"];~%")
          (dolist (succ (basic-block-succ bb))
            (format out "~A -> ~A~%" (basic-block-id bb) (basic-block-id succ))))
        (write-line "}" out)))
    #+sbcl
    (progn
      (uiop:run-program (format nil "dot -Tpng '~A' > '~A'" dot-filename img-filename))
      (when open-viewer-p
        #+linux (uiop:run-program (format nil "xdg-open '~A'" img-filename))
        #+os-macosx (uiop:run-program (format nil "open '~A'" img-filename))))))

(defun graphviz-dominator-tree (d-tree)
  (let ((dot-filename "/tmp/d-tree.dot")
        (img-filename "/tmp/d-tree.png"))
    (with-open-file (out dot-filename
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (write-line "digraph dominator_tree {" out)
      (dolist (node d-tree)
        (format out "~A -> ~A~%" (second node) (first node)))
      (write-line "}" out))
    #+sbcl
    (progn
      (uiop:run-program (format nil "dot -Tpng '~A' > '~A'" dot-filename img-filename))
      #+linux (uiop:run-program (format nil "xdg-open '~A'" img-filename))
      #+os-macosx (uiop:run-program (format nil "open '~A'" img-filename)))))

(defun test (&optional (open-viewer-p t))
  (let* ((hir (let ((*gensym-counter* 0))
                (pass1-toplevel #+(or)
                                '(tagbody
                                  a
                                  (if x (go b) (go c))
                                  b
                                  (print 1)
                                  (go d)
                                  c
                                  (print 2)
                                  (go d)
                                  d
                                  (print 3)
                                  (go a))
                                #+(or)
                                '(dotimes (i 10)
                                  (dotimes (j 20)
                                    (f i j)))
                                ;#+(or)
                                '(dotimes (i 10)
                                  (if x
                                      (f)
                                      (g))))))
         (compiland (create-compiland hir)))
    ;; (pprint (reduce-hir hir))

    (remove-unused-block compiland)
    (remove-unused-label compiland)
    ;; (merge-basic-blocks compiland)

    (graphviz-compiland compiland "valtan-1" open-viewer-p)

    (defparameter $d-table (create-dominator-table compiland))
    (defparameter $loop-graph (create-loop-graph compiland $d-table))
    (defparameter $d-tree (create-dominator-tree $d-table))

    (graphviz-dominator-tree $d-tree)
    ))
