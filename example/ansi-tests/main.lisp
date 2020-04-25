(ffi:require js:fs "fs")

(defun test (filename)
  (format t "test: ~A~%" filename)
  (with-open-file (in filename)
    (let ((eof-value (gensym)))
      (do ((form (read in nil eof-value) (read in nil eof-value))
           (n 0 (1+ n)))
          ((eq form eof-value))
        (cond ((eval form)
               (format t "~D Pass: ~S~%" n form))
              (t
               (format t "~D Failed: ~S~%" n form)))))))

(defmacro time (form)
  (let ((start (gensym)))
    `(let ((,start (js:-date.now)))
       ,form
       (format t "~&time: ~A~%" (- (js:-date.now) ,start)))))


(test "sacla-tests/must-array.lisp")

#|
(time (progn
;; (test "sacla-tests/desirable-printer.lisp")
;; (test "sacla-tests/must-array.lisp")
(test "sacla-tests/must-character.lisp")
(test "sacla-tests/must-condition.lisp")
(test "sacla-tests/must-cons.lisp")
;; (test "sacla-tests/must-data-and-control.lisp")
(test "sacla-tests/must-do.lisp")
(test "sacla-tests/must-eval.lisp")
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
))
;|#
