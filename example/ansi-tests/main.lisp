(ffi:require js:fs "fs")

(defun test (filename)
  (with-open-file (in filename)
    (let ((eof-value '#:eof)
          (fail-forms '())
          (error-forms '()))
      (do ((form (read in nil eof-value) (read in nil eof-value)))
          ((eq form eof-value))
        (prin1 form)
        (terpri)
        (let ((result (eval form)))
          (print result)
          (terpri)
          (unless result
            (push form fail-forms))))
      (terpri)
      (terpri)
      (write-line "==================== FAIL FORMS ====================")
      (dolist (form (nreverse fail-forms))
        (prin1 form)
        (terpri)))))

(defmacro time (form)
  (let ((start (gensym)))
    `(let ((,start (js:-date.now)))
       ,form
       (format t "~&time: ~A~%" (- (js:-date.now) ,start)))))

;; (test "sacla-tests/desirable-printer.lisp")
;; (test "sacla-tests/must-array.lisp")
(test "sacla-tests/must-character.lisp")
(test "sacla-tests/must-condition.lisp")
(test "sacla-tests/must-cons.lisp")
;; (test "sacla-tests/must-data-and-control.lisp")
(test "sacla-tests/must-do.lisp")
;; (test "sacla-tests/must-eval.lisp")
;; (test "sacla-tests/must-hash-table.lisp")
;; (test "sacla-tests/must-loop.lisp")
;; (test "sacla-tests/must-package.lisp")
;; (test "sacla-tests/must-printer.lisp")
;; (test "sacla-tests/must-reader.lisp")
(test "sacla-tests/must-sequence.lisp")
(test "sacla-tests/must-string.lisp")
(test "sacla-tests/must-symbol.lisp")
;; (test "sacla-tests/should-array.lisp")
(test "sacla-tests/should-character.lisp")
(test "sacla-tests/should-cons.lisp")
;; (test "sacla-tests/should-data-and-control.lisp")
;; (test "sacla-tests/should-eval.lisp")
;; (test "sacla-tests/should-hash-table.lisp")
;; (test "sacla-tests/should-package.lisp")
;; (test "sacla-tests/should-sequence.lisp")
(test "sacla-tests/should-string.lisp")
(test "sacla-tests/should-symbol.lisp")
;; (test "sacla-tests/x-sequence.lisp")
