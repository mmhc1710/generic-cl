;;;; sequences.lisp
;;;;
;;;; Copyright 2019 Alexander Gutev
;;;;
;;;; Permission is hereby granted, free of charge, to any person
;;;; obtaining a copy of this software and associated documentation
;;;; files (the "Software"), to deal in the Software without
;;;; restriction, including without limitation the rights to use,
;;;; copy, modify, merge, publish, distribute, sublicense, and/or sell
;;;; copies of the Software, and to permit persons to whom the
;;;; Software is furnished to do so, subject to the following
;;;; conditions:
;;;;
;;;; The above copyright notice and this permission notice shall be
;;;; included in all copies or substantial portions of the Software.
;;;;
;;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
;;;; OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;;; NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;;;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;;;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;;;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
;;;; OTHER DEALINGS IN THE SOFTWARE.

;;;; Unit tests for the generic sequences interface

(in-package :generic-cl.test)

(plan nil)


;; Custom Sequence Type

(defstruct list-wrapper
  "Custom sequence type used for testing the generic sequence
   functions. The sequence simply wraps a list which is stored in the
   LIST slot."

  list)

(defun list-wrap (&rest elems)
  "Create a `LIST-WRAPPER' with elements ELEMS."

  (make-list-wrapper :list elems))

(defmethod equalp ((a list-wrapper) (b list-wrapper))
  (equalp (list-wrapper-list a) (list-wrapper-list b)))


;; Custom Sequence Iterator

(defstruct (list-wrapper-iterator (:include iterator)
				  (:copier nil))

  "Custom Sequence Iterator."
  it)

(defmethod make-iterator ((seq list-wrapper) start end)
  (make-list-wrapper-iterator :it (make-iterator (list-wrapper-list seq) start end)))

(defmethod make-reverse-iterator ((seq list-wrapper) start end)
  (make-list-wrapper-iterator :it (make-reverse-iterator (list-wrapper-list seq) start end)))

(defmethod copy ((it list-wrapper-iterator) &key)
  (make-list-wrapper-iterator :it (copy (list-wrapper-iterator-it it))))


(defmethod at ((it list-wrapper-iterator))
  (at (list-wrapper-iterator-it it)))

(defmethod (setf at) (value (it list-wrapper-iterator))
  (setf (at (list-wrapper-iterator-it it)) value))

(defmethod advance ((it list-wrapper-iterator))
  (advance (list-wrapper-iterator-it it)))

(defmethod endp ((it list-wrapper-iterator))
  (endp (list-wrapper-iterator-it it)))


;;; Custom Sequence Collector

(defmethod cleared ((seq list-wrapper) &key)
  (make-list-wrapper))

(defmethod make-sequence-of-type ((type (eql 'list-wrapper)) (args t))
  (make-list-wrapper))


(defstruct list-wrapper-collector
  "Custom Sequence Collector."

  collector)

(defmethod make-collector ((seq list-wrapper) &key front)
  (make-list-wrapper-collector :collector (make-collector (list-wrapper-list seq) :front front)))

(defmethod accumulate ((c list-wrapper-collector) item)
  (accumulate (list-wrapper-collector-collector c) item))

(defmethod collector-sequence ((c list-wrapper-collector))
  (make-list-wrapper :list (collector-sequence (list-wrapper-collector-collector c))))

(macrolet ((test-seq-fn ((&rest lists) &body tests)
	     "Tests a function on a CL:SEQUENCE and LIST-WRAPPER simultaneously.
              Each element of LISTS is of the form (SYM LIST) where
              SYM is a symbol and list is a LIST (evaluated). The
              forms in TESTS are evaluated twice, first with each SYM
              bound to the corresponding LIST, then with each SYM
              bound to a `LIST-WRAPPER' with the contents of the
              corresponding LIST. Both bindings are established by
              SYMBOL-MACROLET."

	     `(progn
		(symbol-macrolet ,lists
		  (diag "CL Sequence")
		  ,@tests)
		(symbol-macrolet
		    ,(loop for (var list) in lists
			collect `(,var (make-list-wrapper :list ,list)))
		  (diag "Generic Sequence")
		  ,@tests)))

	   (test-not-modified ((&rest seqs) &body tests)
	     "Tests that a sequence is not modified after the
              evaluation of TESTS. Each element of SEQS is of the
              form (SYM SEQ) where SYM is the symbol to which the
              result of the evaluation of SEQ is bound. Tests are
              evaluated in the environment of the bindings to each
              SYM. After the evaluation of TESTS, further tests are
              performed that check whether each SYM is equal to the
              corresponding SEQ."

	     `(progn
		(let ,seqs
		  ,@tests
		  ,@(loop for (var seq) in seqs
		       collect `(is ,var ,seq :test #'equalp "Not Modified")))))

	   (ok-form (form)
	     "Tests whether FORM evaluates to true with FORM as the
              test description."
	     `(ok ,form (format nil "~s" ',form))))

  (subtest "Test Sequence Functions"
    (subtest "Test LENGTH"
      (is (length '(1 2 3 4)) 4)
      (is (length #(a b c d e)) 5)
      (is (length (make-array 7 :adjustable t :initial-element 0 :fill-pointer 3)) 3)
      (is (length (alist-hash-map '((a . 1) (b . 2) (c . 3)))) 3))

    (subtest "Test EMPTYP"
      (ok (emptyp nil))
      (ok (emptyp (make-hash-map)))
      (ok (list-wrap))

      (ok (not (emptyp '(1 2 3))))
      (ok (not (emptyp #(a b c))))
      (ok (not (emptyp #2A((1 2 3) (4 5 6)))))
      (ok (not (emptyp (alist-hash-map '((a . 1) (b . 2))))))
      (ok (not (emptyp (list-wrap 1 2 3)))))

    (subtest "Test CLEAR"
      (alet (make-array 5 :initial-contents '(1 2 3 4 5) :adjustable t)
	(clear it)
	(is (cl:length it) 0))

      (alet (make-array 5 :initial-contents '(1 2 3 4 5) :adjustable t :fill-pointer t)
	(clear it)
	(is (cl:length it) 0))

      (is-error (clear #(1 2 3)) 'type-error))

    (subtest "Test ELT"
      (loop for i below 4
	 do
	   (diag (format nil "Index = ~s" i))
	   (is (elt '(1 2 3 4) i) (cl:elt '(1 2 3 4) i))
	   (is (elt #(a b c d) i) (cl:elt #(a b c d) i))
	   (is (elt #2A((1 2) (3 4)) i) (row-major-aref #2A((1 2) (3 4)) i))
	   (is (elt (list-wrap 'w 'x 'y 'z) i) (nth i '(w x y z)))))

    (subtest "Test (SETF ELT)"
      (alet (list 1 2 3 4)
	(is (setf (elt it 2) 'x) 'x)
	(is it '(1 2 x 4)))

      (alet (vector 1 2 3 4)
	(is (setf (elt it 1) 'x) 'x)
	(is it #(1 x 3 4) :test #'equalp))

      (alet (make-array '(2 2) :initial-contents '((1 2) (3 4)))
	(is (setf (elt it 3) 'a) 'a)
	(is (setf (elt it 0) 'b) 'b)
	(is it #2A((b 2) (3 a)) :test #'equalp))

      (alet (list-wrap 1 2 3 4)
	(is (setf (elt it 2) 'z) 'z)
	(is it (list-wrap 1 2 'z 4) :test #'equalp)))

    (subtest "Test FIRST"
      (is (first '(1 2 3 4)) 1)
      (is (first #(a b c d)) 'a)
      (is (first #2A((1 2) (3 4))) 1)
      (is (first (list-wrap 'x 'y 'z)) 'x))

    (subtest "Test LAST"
      (is (last '(1 2 3 4)) 4)
      (is (last #(a b c d)) 'd)
      (is (last #2A((1 2) (3 4))) 4)
      (is (last (list-wrap 'x 'y 'z)) 'z)

      (macrolet ((test-last (seq n)
		   `(is (last ,seq ,n) (elt ,seq (- (length ,seq) 1 ,n)))))
	(loop for n below 4
	   do
	     (diag (format nil "N = ~s" n))
	     (test-last '(1 2 3 4) n)
	     (test-last #(a b c d) n)
	     (test-last #2A((1 2) (3 4)) n)
	     (test-last (list-wrap 'w 'x 'y 'z) n))))

    (subtest "Test LASTCDR"
      (let ((list '(1 2 3 4)))
	(is (lastcdr list) (cl:last list) :test #'eq)
	(is (lastcdr list 1) (cl:last list 1) :test #'eq)
	(is (lastcdr list 3) (cl:last list 3) :test #'eq)))

    (subtest "Test ERASE"
      (alet (make-array 5 :initial-contents '(1 2 3 4 5) :adjustable t)
	(erase it 2)
	(is it #(1 2 4 5) :test #'equalp)

	(erase it 0)
	(is it #(2 4 5) :test #'equalp))

      (alet (make-array 5 :initial-contents '(1 2 3 4 5) :adjustable t :fill-pointer t)
	(erase it 2)
	(is it #(1 2 4 5) :test #'equalp)

	(erase it 0)
	(is it #(2 4 5) :test #'equalp))

      (is-error (erase #(1 2 3 4) 1) 'type-error))

    (subtest "Test SUBSEQ"
      (diag "CL Sequences")
      (is (subseq '(1 2 3 4 5) 1 3) '(2 3))
      (is (subseq '(1 2 3 4 5) 2) '(3 4 5))

      (diag "Generic Sequences")
      (is (subseq (make-list-wrapper :list '(1 2 3 4 5)) 1 3)
	  (make-list-wrapper :list '(2 3))
	  :test #'equalp)
      (is (subseq (make-list-wrapper :list '(1 2 3 4 5)) 2)
	  (make-list-wrapper :list '(3 4 5))
	  :test #'equalp)

      (subtest "Test SETF Methods"
	(diag "CL Sequences")
	(let ((list (list 1 2 3 4 5)))
	  (setf (subseq list 1 3) '(x y))
	  (is list '(1 x y 4 5)))

	(diag "Generic Sequences")
	(let ((wrapper (make-list-wrapper :list '(1 2 3 4 5))))
	  (setf (subseq wrapper 1 3) '(x y))
	  (is wrapper (make-list-wrapper :list '(1 x y 4 5)) :test #'equalp))))

    (subtest "Test FILL"
      (test-seq-fn
       ((seq (list 1 2 3 4 5))
	(res  '(a a a a a)))
       (is (fill seq 'a) res :test #'equalp))

      (test-seq-fn
       ((seq (list 1 2 3 4 5))
	(res  '(1 2 0 0 0)))
       (is (fill seq 0 :start 2) res :test #'equalp))

      (test-seq-fn
       ((seq (list 1 2 3 4 5))
	(res  '(1 0 0 4 5)))
       (is (fill seq 0 :start 1 :end 3) res :test #'equalp)))

    (subtest "Test REPLACE"
      (test-seq-fn
       ((seq1 (list 1 2 3 4 5))
	(seq2 '(x y))
	(res '(x y 3 4 5)))
       (is (replace seq1 seq2) res :test #'equalp))

      (test-seq-fn
       ((seq1 (list 1 2 3 4 5))
	(seq2 '(w x y))
	(res '(1 2 x y 5)))
       (is (replace seq1 seq2 :start1 2 :start2 1) res :test #'equalp))

      (test-seq-fn
       ((seq1 (list 1 2 3 4 5))
	(seq2 '(w x y z))
	(res '(1 x y 4 5)))
       (is (replace seq1 seq2 :start1 1 :end1 4 :start2 1 :end2 3) res :test #'equalp))

      (test-seq-fn
       ((seq1 (list 1 2 3 4 5))
	(seq2 '(w x y z))
	(res '(1 x 3 4 5)))
       (is (replace seq1 seq2 :start1 1 :end1 2 :start2 1 :end2 3) res :test #'equalp)))

    (subtest "Test REDUCE"
      (subtest "Left Reduction (:FROM-END NIL)"
	(test-seq-fn
	 ((seq '(1 2 3 4)))

	 (is (reduce #'list seq) '(((1 2) 3) 4))
	 (is (reduce #'list seq :initial-value 0) '((((0 1) 2) 3) 4))
	 (is (reduce #'list seq :initial-value 0 :key #'1+) '((((0 2) 3) 4) 5))
	 (is (reduce #'list seq :start 2) '(3 4))
	 (is (reduce #'list seq :start 1 :end 3) '(2 3)))

	(test-seq-fn
	 ((seq nil))
	 (is (reduce #'cl:+ seq) 0)
	 (is (reduce #'list seq :initial-value 1) 1)
	 (is (reduce #'list seq :initial-value 1 :key #'1+) 1))

	(test-seq-fn
	 ((seq '(1)))
	 (is (reduce #'cl:+ seq) 1)
	 (is (reduce #'cl:+ seq :initial-value 2) 3)))

      (subtest "Right Reduction (:FROM-END T)"
	(test-seq-fn
	 ((seq '(1 2 3 4)))
	 (is (reduce #'list seq :from-end t) '(1 (2 (3 4))))
	 (is (reduce #'list seq :initial-value 0 :from-end t) '(1 (2 (3 (4 0)))))
	 (is (reduce #'list seq :initial-value 0 :key #'1+ :from-end t) '(2 (3 (4 (5 0)))))
	 (is (reduce #'list seq :start 2 :from-end t) '(3 4))
	 (is (reduce #'list seq :start 1 :end 3 :from-end t) '(2 3)))

	(test-seq-fn
	 ((seq nil))
	 (is (reduce #'cl:+ seq :from-end t) 0)
	 (is (reduce #'list seq :initial-value 1 :from-end t) 1)
	 (is (reduce #'list seq :initial-value 1 :key #'1+ :from-end t) 1))

	(test-seq-fn
	 ((seq '(1)))
	 (is (reduce #'cl:+ seq :from-end t) 1)
	 (is (reduce #'list seq :initial-value 2 :from-end t) '(1 2)))))

    (subtest "Test COUNT Functions"
      (subtest "Test COUNT"
	(test-seq-fn
	 ((seq '("a" "b" "c" "a" "d")))

	 (is (count "a" seq) 2)
	 (is (count "a" seq :from-end t) 2)
	 (is (count "a" seq :start 1) 1)
	 (is (count "a" seq :start 1 :end 3) 0)
	 (is (count "A" seq :key #'string-upcase) 2))

	(test-seq-fn
	 ((seq '(0 1 2 0 3)))
	 (is (count 1 seq :key #'1+) 2))

	(test-seq-fn
	 ((seq nil))
	 (is (count 'x seq) 0)))

      (subtest "Test COUNT-IF"
	(test-seq-fn
	 ((seq '(1 2 3 4 5)))

	 (is (count-if #'evenp seq) 2)
	 (is (count-if #'evenp seq :from-end t) 2)
	 (is (count-if #'evenp seq :start 2) 1)
	 (is (count-if #'evenp seq :start 2 :end 3) 0))

	(test-seq-fn
	 ((seq '(0 1 2 0 3)))
	 (is (count-if (curry #'< 2) seq :key #'1+) 2))

	(test-seq-fn
	 ((seq nil))
	 (is (count-if #'evenp seq) 0)))

      (subtest "Test COUNT-IF-NOT"
	(test-seq-fn
	 ((seq '(1 2 3 4 5)))

	 (is (count-if-not #'evenp seq) 3)
	 (is (count-if-not #'evenp seq :from-end t) 3)
	 (is (count-if-not #'evenp seq :start 2) 2)
	 (is (count-if-not #'evenp seq :start 2 :end 3) 1))

	(test-seq-fn
	 ((seq '(0 1 2 0 3)))
	 (is (count-if-not (curry #'< 2) seq :key #'1+) 3))

	(test-seq-fn
	 ((seq nil))
	 (is (count-if-not #'evenp seq) 0))))

    (subtest "Test FIND Functions"
      (subtest "Test FIND"
	(test-seq-fn
	 ((seq '("b" "a" "c" "d" "a")))

	 (is (find "a" seq) "a")
	 (is (find "a" seq :from-end t) "a")
	 (is (find "a" seq :start 2) "a")
	 (is (find "a" seq :start 2 :end 3) nil))

	(test-seq-fn
	 ((seq '(1 3 5 6)))
	 (is (find 2 seq :key #'1+) 1))

	(test-seq-fn
	 ((seq nil))
	 (is (find 'x seq) nil)))

      (subtest "Test FIND-IF"
	(test-seq-fn
	 ((seq '(1 3 4 5 6 7))
	  (empty nil))

	 (is (find-if #'evenp seq) 4)
	 (is (find-if #'evenp seq :from-end t) 6)
	 (is (find-if #'evenp seq :start 3) 6)
	 (is (find-if #'evenp seq :start 3 :end 4) nil)
	 (is (find-if #'evenp seq :key #'1+) 1)

	 (is (find-if #'evenp empty) nil)))

      (subtest "Test FIND-IF-NOT"
	(test-seq-fn
	 ((seq '(1 3 4 5 6 7))
	  (empty nil))

	 (is (find-if-not #'evenp seq) 1)
	 (is (find-if-not #'evenp seq :from-end t) 7)
	 (is (find-if-not #'evenp seq :start 3) 5)
	 (is (find-if-not #'evenp seq :start 2 :end 3) nil)
	 (is (find-if-not #'evenp seq :key #'1+) 4)

	 (is (find-if-not #'evenp empty) nil))))

    (subtest "Test POSITION Functions"
      (subtest "Test POSITION"
	(test-seq-fn
	 ((seq '("b" "a" "c" "d" "a")))

	 (is (position "a" seq) 1)
	 (is (position "a" seq :from-end t) 4)
	 (is (position "a" seq :start 2) 4)
	 (is (position "a" seq :start 2 :end 3) nil))

	(test-seq-fn
	 ((seq '(1 3 5 6)))
	 (is (position 2 seq :key #'1+) 0))

	(test-seq-fn
	 ((seq nil))
	 (is (position 'x seq) nil)))

      (subtest "Test POSITION-IF"
	(test-seq-fn
	 ((seq '(1 3 4 5 6 7)))

	 (is (position-if #'evenp seq) 2)
	 (is (position-if #'evenp seq :from-end t) 4)
	 (is (position-if #'evenp seq :start 3) 4)
	 (is (position-if #'evenp seq :start 3 :end 4) nil)
	 (is (position-if #'evenp seq :key #'1+) 0))

	(test-seq-fn
	 ((seq nil))
	 (is (position-if #'evenp seq) nil)))

      (subtest "Test POSITION-IF-NOT"
	(test-seq-fn
	 ((seq '(1 3 4 5 6 7)))

	 (is (position-if-not #'evenp seq) 0)
	 (is (position-if-not #'evenp seq :start 3) 3)
	 (is (position-if-not #'evenp seq :start 2 :end 3) nil)
	 (is (position-if-not #'evenp seq :key #'1+) 2))

	(is (position-if-not #'evenp '(1 3 4 5 6 7) :from-end t) 5)

	(test-seq-fn
	 ((seq nil))
	 (is (position-if-not #'evenp seq) nil))))

    (subtest "Test SEARCH"
      (test-seq-fn
       ((seq1 '("alex" "bob"))
	(seq2 '("pete" "alex" "bob" "john" "alex" "jack" "alex" "bob" "jack"))
	(seq3 nil))

       (is (search seq1 seq2) 1)
       (is (search seq1 seq2 :from-end t) 6)
       (is (search seq1 seq2 :start2 2) 6)
       (is (search seq1 seq2 :start1 1 :start2 2) 2)
       (is (search seq1 seq2 :end2 2) nil)
       (is (search seq1 seq2 :end1 1 :end2 2) 1)
       (is (search seq1 seq2 :start1 0 :start2 3 :end1 1 :end2 5) 4)

       (is (search '("Alex" "BOB") seq2 :key #'string-upcase) 1)

       ;; Empty Sequences
       (is (search seq1 seq2 :start1 1 :start2 2 :end1 1) 2)
       (is (search seq3 seq2) 0))

      (test-seq-fn
       ((seq1 '((x 2) (y 3)))
	(seq2 '((a 1) (b 2) (c 3) (d 4))))

       ;; Test :KEY argument
       (is (search seq1 seq2 :key #'cadr) 1)))

    (subtest "Test MISMATCH"
      (test-seq-fn
       ((seq '("alex" "bob" "john" "jack")))

       (is (mismatch seq '("alex" "bob" "john" "jack")) nil)
       (is (mismatch seq '("alex" "Bob" "john" "Jack")) 1)
       (is (mismatch seq '("alex" "bob")) 2)
       (is (mismatch '("alex" "bob") seq) 2)
       (is (mismatch seq '("alex" "Bob" "john" "Jack") :key #'string-upcase) nil)
       (is (mismatch seq '("alex" "Bob" "john" "Jack") :from-end t) 4)
       (is (mismatch seq '("bob" "john" "jack") :start1 1) nil)
       (is (mismatch seq '("Alex" "Pete" "bob" "john" "jack") :start1 1 :start2 2) nil)
       (is (mismatch seq '("Alex" "Pete" "bob" "John" "jack") :start1 1 :start2 2) 2)
       (is (mismatch seq '("Alex" "alex" "bob" "john" "Pete" "jack") :start1 1 :end1 3 :start2 2 :end2 4) nil)

       (diag "Empty Sequences")

       (is (mismatch seq seq :start2 1 :end2 1) 0)
       (is (mismatch seq seq :start1 1 :end1 1) 1)
       (is (mismatch seq nil) 0)
       (is (mismatch nil seq) 0))

      (test-seq-fn
       ((seq '("alex" "john" "jack" "bob")))

       (is (mismatch seq '("alex" "bob" "john" "jack" "pete") :from-end t :start1 1 :end1 3 :start2 2 :end2 4) nil)
       (is (mismatch seq '("alex" "bob" "john" "jack" "pete") :from-end t :end1 3 :end2 4) 1)))

    (subtest "Test Reversing"
      (subtest "Test REVERSE"
	(diag "CL Sequences")

	(test-seq-fn
	 ((list '(1 2 3 4))
	  (res '(4 3 2 1)))

	 (test-not-modified
	  ((seq list))
	  (is (reverse seq) res :test #'equalp)))

	(test-seq-fn
	 ((seq '(1))
	  (res '(1)))
	 (is (reverse seq) res :test #'equalp))

	(test-seq-fn
	 ((seq nil)
	  (res nil))
	 (is (reverse seq) res :test #'equalp))

	(is (reverse #(a b c d)) #(d c b a) :test #'equalp))

      (subtest "Test NREVERSE"
	(test-seq-fn
	 ((seq (list 1 2 3 4))
	  (res (list 4 3 2 1)))
	 (is (nreverse seq) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1))
	  (res (list 1)))
	 (is (nreverse seq) res :test #'equalp))

	(test-seq-fn
	 ((seq nil)
	  (res nil))
	 (is (nreverse seq) res :test #'equalp))

	(is (nreverse (vector 'a 'b 'c 'd)) #(d c b a) :test #'equalp)))

    (subtest "Test Merging"
      (subtest "Test MERGE"
	(diag "CL Sequences")

	(test-seq-fn
	 ((list1 '(1 2 3 4))
	  (list2 '(5 6 7 8))
	  (res '(1 2 3 4 5 6 7 8)))

	 (test-not-modified
	  ((seq1 list1)
	   (seq2 list2))

	  (is (merge seq1 seq2 #'lessp) res :test #'equalp)))

	(test-seq-fn
	 ((list1 '(1 3 5 9))
	  (list2 '(2 4 6 7 8))
	  (res '(1 2 3 4 5 6 7 8 9)))

	 (test-not-modified
	  ((seq1 list1)
	   (seq2 list2))

	  (is (merge seq1 seq2 #'lessp) res :test #'equalp)))

	(test-seq-fn
	 ((seq1 '((a 1) (b 2) (c 5) (d 8)))
	  (seq2 '((e 3) (f 4) (g 6) (h 7)))
	  (res '((a 1) (b 2) (e 3) (f 4) (c 5) (g 6) (h 7) (d 8))))
	 (is (merge seq1 seq2 #'lessp :key #'cadr) res :test #'equalp))

	;; Test Stability
	(test-seq-fn
	 ((seq1 '((b 1) (d 1) (a 99)))
	  (seq2 '((e 1) (h 1) (f 32) (c 74)))
	  (res '((b 1) (d 1) (e 1) (h 1) (f 32) (c 74) (a 99))))
	 (is (merge seq1 seq2 #'lessp :key #'cadr) res :test #'equalp))

	;; Empty Sequences
	(test-seq-fn
	 ((seq '(1 2 3 4))
	  (empty nil))
	 (is (merge seq nil #'lessp) seq :test #'equalp)
	 (is (merge empty seq #'lessp) seq :test #'equalp)))

      (subtest "Test NMERGE"
	(diag "CL Sequences")

	(test-seq-fn
	 ((seq1 (list 1 2 3 4))
	  (seq2 (list 5 6 7 8))
	  (res '(1 2 3 4 5 6 7 8)))
	 (is (nmerge seq1 seq2 #'lessp) res :test #'equalp))

	(test-seq-fn
	 ((seq1 (list 1 3 5 9))
	  (seq2 (list 2 4 6 7 8))
	  (res '(1 2 3 4 5 6 7 8 9)))
	 (is (nmerge seq1 seq2 #'lessp) res :test #'equalp))

	(test-seq-fn
	 ((seq1 (list '(a 1) '(b 2) '(c 5) '(d 8)))
	  (seq2 (list '(e 3) '(f 4) '(g 6) '(h 7)))
	  (res '((a 1) (b 2) (e 3) (f 4) (c 5) (g 6) (h 7) (d 8))))
	 (is (nmerge seq1 seq2 #'lessp :key #'cadr) res :test #'equalp))

	;; Test Stability
	(test-seq-fn
	 ((seq1 (list '(b 1) '(d 1) '(a 99)))
	  (seq2 (list '(e 1) '(h 1) '(f 32) '(c 74)))
	  (res '((b 1) (d 1) (e 1) (h 1) (f 32) (c 74) (a 99))))
	 (is (nmerge seq1 seq2 #'lessp :key #'cadr) res :test #'equalp))

	;; Empty Sequences
	(test-seq-fn
	 ((seq (list 1 2 3 4))
	  (empty nil))
	 (is (nmerge seq nil #'lessp) seq :test #'equalp)
	 (is (nmerge empty seq #'lessp) seq :test #'equalp))))

    (subtest "Test Sorting"
      (subtest "Test SORT Functions"
	(subtest "Test SORT"
	  (diag "CL Sequences")

	  (test-seq-fn
	   ((list '("aac" "zzz" "aaa" "aab" "bac" "baa"))
	    (res '("aaa" "aab" "aac" "baa" "bac" "zzz")))

	   (test-not-modified
	    ((seq list))
	    (is (sort seq) res :test #'equalp)))

	  (test-seq-fn
	   ((seq '(99 3 74 56 1 32 49))
	    (res '(99 74 56 49 32 3 1)))
	   (is (sort seq :test #'greaterp) res :test #'equalp))

	  (test-seq-fn
	   ((seq '((a 99) (b 3) (c 74) (d 56) (e 1) (f 32) (h 49)))
	    (res '((e 1) (b 3) (f 32) (h 49) (d 56) (c 74) (a 99))))
	   (is (sort seq :key #'cadr) res :test #'equalp))

	  ;; Empty Sequence
	  (test-seq-fn
	   ((seq nil))
	   (is (sort seq) seq :test #'equalp))

	  ;; Other CL Sequences
	  (is (sort #(99 3 74 56 1 32 49) :test #'greaterp) #(99 74 56 49 32 3 1) :test #'equalp))

	(subtest "Test NSORT"
	  (test-seq-fn
	   ((seq (list "aac" "zzz" "aaa" "aab" "bac" "baa"))
	    (res '("aaa" "aab" "aac" "baa" "bac" "zzz")))
	   (is (nsort seq) res :test #'equalp))

	  (test-seq-fn
	   ((seq (list 99 3 74 56 1 32 49))
	    (res '(99 74 56 49 32 3 1)))
	   (is (nsort seq :test #'greaterp) res :test #'equalp))

	  (test-seq-fn
	   ((seq (list '(a 99) '(b 3) '(c 74) '(d 56) '(e 1) '(f 32) '(h 49)))
	    (res '((e 1) (b 3) (f 32) (h 49) (d 56) (c 74) (a 99))))
	   (is (nsort seq :key #'cadr) res :test #'equalp))

	  ;; Empty Sequence
	  (test-seq-fn
	   ((seq nil))
	   (is (nsort seq) seq :test #'equalp))

	  ;; Other CL Sequences
	  (is (nsort (vector 99 3 74 56 1 32 49) :test #'greaterp) #(99 74 56 49 32 3 1) :test #'equalp)))

      (subtest "Test STABLE-SORT Functions"
	(subtest "Test STABLE-SORT"
	  (test-seq-fn
	   ((list '("aac" "zzz" "aaa" "aab" "bac" "baa"))
	    (res '("aaa" "aab" "aac" "baa" "bac" "zzz")))

	   (test-not-modified
	    ((seq list))
	    (is (stable-sort seq) res :test #'equalp)))

	  (test-seq-fn
	   ((seq '(99 3 74 56 1 32 49))
	    (res '(99 74 56 49 32 3 1)))
	   (is (stable-sort seq :test #'greaterp) res :test #'equalp))

	  (test-seq-fn
	   ((seq '(99 3 74 56 1 32 49))
	    (res '(99 74 56 49 32 3 1)))
	   (is (stable-sort seq :test #'greaterp) res :test #'equalp))

	  (is (stable-sort #(99 3 74 56 1 32 49) :test #'greaterp) #(99 74 56 49 32 3 1) :test #'equalp)

	  ;; Test Stability
	  (test-seq-fn
	   ((seq '((a 99) (b 1) (c 74) (d 1) (e 1) (f 32) (h 1)))
	    (res '((b 1) (d 1) (e 1) (h 1) (f 32) (c 74) (a 99))))
	   (is (stable-sort seq :key #'cadr) res :test #'equalp))

	  ;; Empty Sequence
	  (test-seq-fn
	   ((seq nil))
	   (is (stable-sort seq) seq :test #'equalp)))


	(subtest "Test STABLE-NSORT"
	  (diag "CL Sequences")

	  (test-seq-fn
	   ((seq (list "aac" "zzz" "aaa" "aab" "bac" "baa"))
	    (res (list "aaa" "aab" "aac" "baa" "bac" "zzz")))
	   (is (stable-nsort seq) res :test #'equalp))

	  (test-seq-fn
	   ((seq (list 99 3 74 56 1 32 49))
	    (res '(99 74 56 49 32 3 1)))
	   (is (stable-nsort seq :test #'greaterp) res :test #'equalp))

	  (is (stable-nsort (vector 99 3 74 56 1 32 49) :test #'greaterp) #(99 74 56 49 32 3 1) :test #'equalp)

	  ;; Test Stability
	  (test-seq-fn
	   ((seq (list '(a 99) '(b 1) '(c 74) '(d 1) '(e 1) '(f 32) '(h 1)))
	    (res '((b 1) (d 1) (e 1) (h 1) (f 32) (c 74) (a 99))))
	   (is (stable-nsort seq :key #'cadr) res :test #'equalp))

	  ;; Empty Sequence
	  (test-seq-fn
	   ((seq nil))
	   (is (stable-nsort seq) seq :test #'equalp)))))

    (subtest "Test SUBSTITUTE Functions"
      (subtest "Test SUBSTITUTE"
	(test-seq-fn
	 ((list '("a" "b" "old" "c" "old" "d"))
	  (res '("a" "b" "new" "c" "new" "d")))

	 (test-not-modified
	  ((seq list))
	  (is (substitute "new" "old" seq) res :test #'equalp)))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(x 2 3 x 4 5 x)))
	 (is (substitute 'x 1 seq) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(x 2 3 x 4 5 1)))
	 (is (substitute 'x 1 seq :count 2) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(1 2 3 x 4 5 x)))
	 (is (substitute 'x 1 seq :count 2 :from-end t) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(1 2 3 x 4 5 x)))
	 (is (substitute 'x 1 seq :start 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(1 2 3 x 4 5 1)))
	 (is (substitute 'x 1 seq :start 1 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(1 2 3 x 4 5 1)))
	 (is (substitute 'x 1 seq :start 1 :end 5) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(x 2 3 x 4 5 1)))
	 (is (substitute 'x 1 seq :end 5) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(x 2 3 1 4 5 1)))
	 (is (substitute 'x 1 seq :end 5 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '((a 1) (b 2) (c 3) (d 1) (e 4) (f 5) (g 1)))
	  (res '(x (b 2) (c 3) x (e 4) (f 5) x)))
	 (is (substitute 'x 1 seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (substitute 'y 'x seq) seq :test #'equalp)))

      (subtest "Test NSUBSTITUTE"
	(test-seq-fn
	 ((seq (list "a" "b" "old" "c" "old" "d"))
	  (res (list "a" "b" "new" "c" "new" "d")))

	 (is (nsubstitute "new" "old" seq) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 1 4 5 1))
	  (res (list 'x 2 3 'x 4 5 'x)))
	 (is (nsubstitute 'x 1 seq) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 1 4 5 1))
	  (res (list 'x 2 3 'x 4 5 1)))
	 (is (nsubstitute 'x 1 seq :count 2) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 1 4 5 1))
	  (res (list 1 2 3 'x 4 5 'x)))
	 (is (nsubstitute 'x 1 seq :count 2 :from-end t) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 1 4 5 1))
	  (res (list 1 2 3 'x 4 5 'x)))
	 (is (nsubstitute 'x 1 seq :start 1) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 1 4 5 1))
	  (res (list 1 2 3 'x 4 5 1)))
	 (is (nsubstitute 'x 1 seq :start 1 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 1 4 5 1))
	  (res (list 1 2 3 'x 4 5 1)))
	 (is (nsubstitute 'x 1 seq :start 1 :end 5) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 1 4 5 1))
	  (res (list 'x 2 3 'x 4 5 1)))
	 (is (nsubstitute 'x 1 seq :end 5) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 1 4 5 1))
	  (res (list 'x 2 3 1 4 5 1)))
	 (is (nsubstitute 'x 1 seq :end 5 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq (list '(a 1) '(b 2) '(c 3) '(d 1) '(e 4) '(f 5) '(g 1)))
	  (res (list 'x '(b 2) '(c 3) 'x '(e 4) '(f 5) 'x)))
	 (is (nsubstitute 'x 1 seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (nsubstitute 'y 'x seq) seq :test #'equalp)))

      (subtest "Test SUBSTITUTE-IF"
	(test-seq-fn
	 ((list '(1 2 3 4 5 6 7 8))
	  (res '(1 x 3 x 5 x 7 x)))

	 (test-not-modified
	  ((seq list))
	  (is (substitute-if 'x #'evenp seq) res :test #'equalp)))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 x 3 x 5 6 7 8)))
	 (is (substitute-if 'x #'evenp seq :count 2) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 2 3 4 5 x 7 x)))
	 (is (substitute-if 'x #'evenp seq :count 2 :from-end t) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 2 3 x 5 x 7 x)))
	 (is (substitute-if 'x #'evenp seq :start 2) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 2 3 x 5 6 7 8)))
	 (is (substitute-if 'x #'evenp seq :start 2 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 2 3 x 5 x 7 8)))
	 (is (substitute-if 'x #'evenp seq :start 2 :end 6) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 x 3 x 5 6 7 8)))
	 (is (substitute-if 'x #'evenp seq :end 5) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 x 3 4 5 6 7 8)))
	 (is (substitute-if 'x #'evenp seq :end 5 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '((a 1) (b 2) (c 3) (d 4) (e 5) (f 6) (g 7)))
	  (res '((a 1) x (c 3) x (e 5) x (g 7))))
	 (is (substitute-if 'x #'evenp seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (substitute-if 'y #'evenp seq) seq :test #'equalp)))

      (subtest "Test NSUBSTITUTE-IF"
	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 'x 3 'x 5 'x 7 'x)))

	 (is (substitute-if 'x #'evenp seq) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 'x 3 'x 5 6 7 8)))
	 (is (substitute-if 'x #'evenp seq :count 2) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 2 3 4 5 'x 7 'x)))
	 (is (substitute-if 'x #'evenp seq :count 2 :from-end t) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 2 3 'x 5 'x 7 'x)))
	 (is (substitute-if 'x #'evenp seq :start 2) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 2 3 'x 5 6 7 8)))
	 (is (substitute-if 'x #'evenp seq :start 2 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 2 3 'x 5 'x 7 8)))
	 (is (substitute-if 'x #'evenp seq :start 2 :end 6) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 'x 3 'x 5 6 7 8)))
	 (is (substitute-if 'x #'evenp seq :end 5) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 'x 3 4 5 6 7 8)))
	 (is (substitute-if 'x #'evenp seq :end 5 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq (list '(a 1) '(b 2) '(c 3) '(d 4) '(e 5) '(f 6) '(g 7)))
	  (res (list '(a 1) 'x '(c 3) 'x '(e 5) 'x '(g 7))))
	 (is (substitute-if 'x #'evenp seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (nsubstitute-if 'y #'evenp seq) seq :test #'equalp)))

      (subtest "Test SUBSTITUTE-IF-NOT"
	(test-seq-fn
	 ((list '(1 2 3 4 5 6 7 8))
	  (res '(x 2 x 4 x 6 x 8)))

	 (test-not-modified
	  ((seq list))
	  (is (substitute-if-not 'x #'evenp seq) res :test #'equalp)))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(x 2 x 4 5 6 7 8)))

	 (is (substitute-if-not 'x #'evenp seq :count 2) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 2 3 4 x 6 x 8)))
	 (is (substitute-if-not 'x #'evenp seq :count 2 :from-end t) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 2 x 4 x 6 x 8)))
	 (is (substitute-if-not 'x #'evenp seq :start 2) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 2 x 4 5 6 7 8)))
	 (is (substitute-if-not 'x #'evenp seq :start 2 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(1 2 x 4 x 6 7 8)))
	 (is (substitute-if-not 'x #'evenp seq :start 2 :end 6) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(x 2 x 4 x 6 7 8)))
	 (is (substitute-if-not 'x #'evenp seq :end 5) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 4 5 6 7 8))
	  (res '(x 2 3 4 5 6 7 8)))
	 (is (substitute-if-not 'x #'evenp seq :end 5 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '((a 1) (b 2) (c 3) (d 4) (e 5) (f 6) (g 7)))
	  (res '(x (b 2) x (d 4) x (f 6) x)))
	 (is (substitute-if-not 'x #'evenp seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (substitute-if-not 'y #'evenp seq) seq :test #'equalp)))

      (subtest "Test NSUBSTITUTE-IF-NOT"
	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 'x 2 'x 4 'x 6 'x 8)))

	 (is (nsubstitute-if-not 'x #'evenp seq) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 'x 2 'x 4 5 6 7 8)))

	 (is (nsubstitute-if-not 'x #'evenp seq :count 2) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 2 3 4 'x 6 'x 8)))
	 (is (substitute-if-not 'x #'evenp seq :count 2 :from-end t) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 2 'x 4 'x 6 'x 8)))
	 (is (nsubstitute-if-not 'x #'evenp seq :start 2) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 2 'x 4 5 6 7 8)))
	 (is (nsubstitute-if-not 'x #'evenp seq :start 2 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 1 2 'x 4 'x 6 7 8)))
	 (is (nsubstitute-if-not 'x #'evenp seq :start 2 :end 6) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 'x 2 'x 4 'x 6 7 8)))
	 (is (nsubstitute-if-not 'x #'evenp seq :end 5) res :test #'equalp))

	(test-seq-fn
	 ((seq (list 1 2 3 4 5 6 7 8))
	  (res (list 'x 2 3 4 5 6 7 8)))
	 (is (nsubstitute-if-not 'x #'evenp seq :end 5 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq (list '(a 1) '(b 2) '(c 3) '(d 4) '(e 5) '(f 6) '(g 7)))
	  (res (list 'x '(b 2) 'x '(d 4) 'x '(f 6) 'x)))
	 (is (nsubstitute-if-not 'x #'evenp seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (nsubstitute-if-not 'y #'evenp seq) seq :test #'equalp))))

    (subtest "Test REMOVE Functions"
      (subtest "Test REMOVE"
	(test-seq-fn
	 ((list '("a" "b" "old" "c" "old" "d"))
	  (res '("a" "b" "c" "d")))

	 (test-not-modified
	  ((seq list))
	  (is (remove "old" seq) res :test #'equalp)))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(2 3 4 5)))
	 (is (remove 1 seq) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(2 3 4 5 1)))
	 (is (remove 1 seq :count 2) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(1 2 3 4 5)))
	 (is (remove 1 seq :count 2 :from-end t) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(1 2 3 4 5)))
	 (is (remove 1 seq :start 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(1 2 3 4 5 1)))
	 (is (remove 1 seq :start 1 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(1 2 3 4 5 1)))
	 (is (remove 1 seq :start 1 :end 5) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(2 3 4 5 1)))
	 (is (remove 1 seq :end 5) res :test #'equalp))

	(test-seq-fn
	 ((seq '(1 2 3 1 4 5 1))
	  (res '(2 3 1 4 5 1)))
	 (is (remove 1 seq :end 5 :count 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '((a 1) (b 2) (c 3) (d 1) (e 4) (f 5) (g 1)))
	  (res '((b 2) (c 3) (e 4) (f 5))))
	 (is (remove 1 seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (remove 'x seq) seq :test #'equalp)))

      (subtest "Test DELETE"
      	(test-seq-fn
      	 ((seq (list "a" "b" "old" "c" "old" "d"))
      	  (res (list "a" "b" "c" "d")))

      	 (is (delete "old" seq) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 1 4 5 1))
      	  (res (list 2 3 4 5)))
      	 (is (delete 1 seq) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 1 4 5 1))
      	  (res (list 2 3 4 5 1)))
      	 (is (delete 1 seq :count 2) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 1 4 5 1))
      	  (res (list 1 2 3 4 5)))
      	 (is (delete 1 seq :count 2 :from-end t) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 1 4 5 1))
      	  (res (list 1 2 3 4 5)))
      	 (is (delete 1 seq :start 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 1 4 5 1))
      	  (res (list 1 2 3 4 5 1)))
      	 (is (delete 1 seq :start 1 :count 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 1 4 5 1))
      	  (res (list 1 2 3 4 5 1)))
      	 (is (delete 1 seq :start 1 :end 5) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 1 4 5 1))
      	  (res (list 2 3 4 5 1)))
      	 (is (delete 1 seq :end 5) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 1 4 5 1))
      	  (res (list 2 3 1 4 5 1)))
      	 (is (delete 1 seq :end 5 :count 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list '(a 1) '(b 2) '(c 3) '(d 1) '(e 4) '(f 5) '(g 1)))
      	  (res (list '(b 2) '(c 3) '(e 4) '(f 5))))
      	 (is (delete 1 seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (delete 'x seq) seq :test #'equalp)))

      (subtest "Test REMOVE-IF"
      	(test-seq-fn
      	 ((list '(1 2 3 4 5 6 7 8))
      	  (res '(1 3 5 7)))

      	 (test-not-modified
      	  ((seq list))
      	  (is (remove-if #'evenp seq) res :test #'equalp)))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 3 5 6 7 8)))
      	 (is (remove-if #'evenp seq :count 2) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 2 3 4 5 7)))
      	 (is (remove-if #'evenp seq :count 2 :from-end t) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 2 3 5 7)))
      	 (is (remove-if #'evenp seq :start 2) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 2 3 5 6 7 8)))
      	 (is (remove-if #'evenp seq :start 2 :count 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 2 3 5 7 8)))
      	 (is (remove-if #'evenp seq :start 2 :end 6) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 3 5 6 7 8)))
      	 (is (remove-if #'evenp seq :end 5) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 3 4 5 6 7 8)))
      	 (is (remove-if #'evenp seq :end 5 :count 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '((a 1) (b 2) (c 3) (d 4) (e 5) (f 6) (g 7)))
      	  (res '((a 1) (c 3) (e 5) (g 7))))
      	 (is (remove-if #'evenp seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (remove-if #'evenp seq) seq :test #'equalp)))

      (subtest "Test DELETE-IF"
      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 3 5 7)))

      	 (is (delete-if #'evenp seq) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 3 5 6 7 8)))
      	 (is (delete-if #'evenp seq :count 2) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 2 3 4 5 7)))
      	 (is (delete-if #'evenp seq :count 2 :from-end t) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 2 3 5 7)))
      	 (is (delete-if #'evenp seq :start 2) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 2 3 5 6 7 8)))
      	 (is (delete-if #'evenp seq :start 2 :count 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 2 3 5 7 8)))
      	 (is (delete-if #'evenp seq :start 2 :end 6) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 3 5 6 7 8)))
      	 (is (delete-if #'evenp seq :end 5) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 3 4 5 6 7 8)))
      	 (is (delete-if #'evenp seq :end 5 :count 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list '(a 1) '(b 2) '(c 3) '(d 4) '(e 5) '(f 6) '(g 7)))
      	  (res (list '(a 1) '(c 3) '(e 5) '(g 7))))
      	 (is (delete-if #'evenp seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (delete-if #'evenp seq) seq :test #'equalp)))

      (subtest "Test REMOVE-IF-NOT"
      	(test-seq-fn
      	 ((list '(1 2 3 4 5 6 7 8))
      	  (res '(2 4 6 8)))

      	 (test-not-modified
      	  ((seq list))
      	  (is (remove-if-not #'evenp seq) res :test #'equalp)))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(2 4 5 6 7 8)))

      	 (is (remove-if-not #'evenp seq :count 2) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 2 3 4 6 8)))
      	 (is (remove-if-not #'evenp seq :count 2 :from-end t) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 2 4 6 8)))
      	 (is (remove-if-not #'evenp seq :start 2) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 2 4 5 6 7 8)))
      	 (is (remove-if-not #'evenp seq :start 2 :count 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(1 2 4 6 7 8)))
      	 (is (remove-if-not #'evenp seq :start 2 :end 6) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(2 4 6 7 8)))
      	 (is (remove-if-not #'evenp seq :end 5) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '(1 2 3 4 5 6 7 8))
      	  (res '(2 3 4 5 6 7 8)))
      	 (is (remove-if-not #'evenp seq :end 5 :count 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq '((a 1) (b 2) (c 3) (d 4) (e 5) (f 6) (g 7)))
      	  (res '((b 2) (d 4) (f 6))))
      	 (is (remove-if-not #'evenp seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (remove-if-not #'evenp seq) seq :test #'equalp)))

      (subtest "Test DELETE-IF-NOT"
      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 2 4 6 8)))

      	 (is (delete-if-not #'evenp seq) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 2 4 5 6 7 8)))

      	 (is (delete-if-not #'evenp seq :count 2) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 2 3 4 6 8)))
      	 (is (delete-if-not #'evenp seq :count 2 :from-end t) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 2 4 6 8)))
      	 (is (delete-if-not #'evenp seq :start 2) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 2 4 5 6 7 8)))
      	 (is (delete-if-not #'evenp seq :start 2 :count 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 1 2 4 6 7 8)))
      	 (is (delete-if-not #'evenp seq :start 2 :end 6) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 2 4 6 7 8)))
      	 (is (delete-if-not #'evenp seq :end 5) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list 1 2 3 4 5 6 7 8))
      	  (res (list 2 3 4 5 6 7 8)))
      	 (is (delete-if-not #'evenp seq :end 5 :count 1) res :test #'equalp))

      	(test-seq-fn
      	 ((seq (list '(a 1) '(b 2) '(c 3) '(d 4) '(e 5) '(f 6) '(g 7)))
      	  (res (list '(b 2) '(d 4) '(f 6))))
      	 (is (delete-if-not #'evenp seq :key #'cadr) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))
	 (is (delete-if-not #'evenp seq) seq :test #'equalp))))

    (subtest "Test REMOVE-DUPLICATES Functions"
      (subtest "Test REMOVE-DUPLICATES"
	(test-seq-fn
	 ((list '("alex" "john" "bob" "alex" "jack" "john"))
	  (res '("bob" "alex" "jack" "john")))

	 (test-not-modified
	  ((seq list))
	  (is (remove-duplicates seq) res :test #'equalp)))

	(test-seq-fn
	 ((seq '("alex" "john" "bob" "alex" "jack" "john"))
	  (res '("alex" "john" "bob" "jack")))

	 (is (remove-duplicates seq :from-end t) res :test #'equalp))

	(test-seq-fn
	 ((seq '("alex" "john" "bob" "alex" "jack" "john"))
	  (res '("alex" "bob" "alex" "jack" "john")))

	 (is (remove-duplicates seq :start 1) res :test #'equalp))

	(test-seq-fn
	 ((seq '("alex" "john" "bob" "alex" "jack" "john"))
	  (res '("alex" "john" "bob" "alex" "jack" "john")))

	 (is (remove-duplicates seq :start 1 :end 4) res :test #'equalp))

	(test-seq-fn
	 ((seq '((a 1) (b 2) (c 1) (d 3) (e 2) (f 4)))
	  (res '((c 1) (d 3) (e 2) (f 4))))

	 (is (remove-duplicates seq :key #'cadr) res :test #'equalp))

	(test-seq-fn
	 ((seq '(#\a #\B #\c #\D #\A #\b #\C #\d))
	  (res '(#\a #\B #\c #\D)))

	 (is (remove-duplicates seq :from-end t :test #'char-equal) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))

	 (is (remove-duplicates seq) seq :test #'equalp)))

      (subtest "Test DELETE-DUPLICATES"
	(test-seq-fn
	 ((seq (list "alex" "john" "bob" "alex" "jack" "john"))
	  (res (list "bob" "alex" "jack" "john")))

	 (is (delete-duplicates seq) res :test #'equalp))

	(test-seq-fn
	 ((seq (list "alex" "john" "bob" "alex" "jack" "john"))
	  (res (list "alex" "john" "bob" "jack")))

	 (is (delete-duplicates seq :from-end t) res :test #'equalp))

	(test-seq-fn
	 ((seq (list "alex" "john" "bob" "alex" "jack" "john"))
	  (res (list "alex" "bob" "alex" "jack" "john")))

	 (is (delete-duplicates seq :start 1) res :test #'equalp))

	(test-seq-fn
	 ((seq (list "alex" "john" "bob" "alex" "jack" "john"))
	  (res (list "alex" "john" "bob" "alex" "jack" "john")))

	 (is (delete-duplicates seq :start 1 :end 4) res :test #'equalp))

	(test-seq-fn
	 ((seq (list '(a 1) '(b 2) '(c 1) '(d 3) '(e 2) '(f 4)))
	  (res (list '(c 1) '(d 3) '(e 2) '(f 4))))

	 (is (delete-duplicates seq :key #'cadr) res :test #'equalp))

	(test-seq-fn
	 ((seq (list #\a #\B #\c #\D #\A #\b #\C #\d))
	  (res (list #\a #\B #\c #\D)))

	 (is (delete-duplicates seq :from-end t :test #'char-equal) res :test #'equalp))

	;; Empty Sequence
	(test-seq-fn
	 ((seq nil))

	 (is (delete-duplicates seq) seq :test #'equalp))))

    (subtest "Test Logical Sequence Functions"
      (subtest "Test EVERY"
	(test-seq-fn
	 ((seq1 '(1 2 4 5))
	  (seq2 '(a b c d))
	  (empty nil))

	 (ok-form (every #'numberp seq1))
	 (ok-form (not (every #'evenp seq1)))
	 (ok-form (every #'equalp seq1 seq1))
	 (ok-form (not (every #'equalp seq1 seq2)))

	 ;; Empty Sequences
	 (ok-form (every #'evenp empty))

	 ;; Deliberately use unary function EVENP as it should never
	 ;; be called. If it is called an error should be raised and
	 ;; the test should be aborted.
	 (ok-form (every #'evenp seq1 empty))))

      (subtest "Test SOME"
	(test-seq-fn
	 ((seq1 '(1 2 4 5))
	  (seq2 '(a b c d))
	  (empty nil))

	 (ok-form (not (some #'numberp seq2)))
	 (ok-form (some #'evenp seq1))
	 (ok-form (some #'equalp seq1 seq1))
	 (ok-form (not (some #'equalp seq1 seq2)))

	 ;; Test Return Value
	 (is (some (lambda (x) (and (evenp x) x)) seq1) 2)

	 ;; Empty Sequences
	 (ok-form (not (some #'evenp empty)))

	 ;; Deliberately use unary function EVENP as it should never
	 ;; be called. If it is called an error should be raised and
	 ;; the test should be aborted.
	 (ok-form (not (some #'evenp seq1 empty)))))

      (subtest "Test NOTANY"
	(test-seq-fn
	 ((seq1 '(1 2 4 5))
	  (seq2 '(a b c d))
	  (empty nil))

	 (ok-form (notany #'numberp seq2))
	 (ok-form (not (notany #'evenp seq1)))
	 (ok-form (not (notany #'equalp seq1 seq1)))
	 (ok-form (notany #'equalp seq1 seq2))

	 ;; Empty Sequences
	 (ok-form (notany #'evenp empty))

	 ;; Deliberately use unary function EVENP as it should never
	 ;; be called. If it is called an error should be raised and
	 ;; the test should be aborted.
	 (ok-form (notany #'evenp seq1 empty))))

      (subtest "Test NOTEVERY"
	(test-seq-fn
	 ((seq1 '(1 2 4 5))
	  (seq2 '(a 5 c d))
	  (empty nil))

	 (ok-form (notevery #'evenp seq1))
	 (ok-form (not (notevery #'numberp seq1)))
	 (ok-form (not (notevery #'equalp seq1 seq1)))
	 (ok-form (notevery #'equalp seq1 seq2))

	 ;; Empty Sequences
	 (ok-form (not (notevery #'evenp empty)))

	 ;; Deliberately use unary function EVENP as it should never
	 ;; be called. If it is called an error should be raised and
	 ;; the test should be aborted.
	 (ok-form (not (notevery #'evenp seq1 empty))))))

    (subtest "Test Concatenation functions"
      (subtest "Test CONCATENATE"
	(test-seq-fn
	 ((list1 '(1 2 3))
	  (list2 '(4 5 6))
	  (list3 '(7 8 9))
	  (list4 nil)
	  (res '(1 2 3 4 5 6 7 8 9)))

	 (test-not-modified
	  ((seq1 list1)
	   (seq2 list2)
	   (seq3 list3)
	   (empty list4))
	  (is (concatenate seq1 empty seq2 seq3 empty) res :test #'equalp)))

	(is (concatenate "all" " " "together" " " "now") "all together now" :test #'equalp))

      (subtest "Test NCONCATENATE"
	(test-seq-fn
	 ((seq1 (list 1 2 3))
	  (seq2 (list 4 5 6))
	  (seq3 (list 7 8 9))
	  (empty nil)
	  (res '(1 2 3 4 5 6 7 8 9)))

	 (is (nconcatenate seq1 empty seq2 seq3 empty) res :test #'equalp))

	(is (nconcatenate (make-array 3 :adjustable t :fill-pointer t :initial-contents '(#\a #\l #\l)) " " "together" " " "now")
	    "all together now" :test #'equalp))

      (subtest "Test CONCATENATE-TO"
	(test-seq-fn
	 ((seq1 (list 1 2 3))
	  (seq2 (list 4 5 6))
	  (seq3 (list 7 8 9))
	  (hello (list #\h #\e #\l #\l #\o #\Space))
	  (world (list #\w #\o #\r #\l #\d))
	  (empty nil))

	 (is (concatenate-to 'list seq1 empty seq2 seq3 empty) '(1 2 3 4 5 6 7 8 9))
	 (is (concatenate-to 'list-wrapper seq1 empty seq2 seq3 empty)
	     (list-wrap 1 2 3 4 5 6 7 8 9)
	     :test #'equalp)
	 (is (concatenate-to 'vector seq1 empty seq2 seq3 empty) #(1 2 3 4 5 6 7 8 9)
	     :test #'equalp)
	 (is (concatenate-to 'string hello world) "hello world"))

	(is (concatenate-to 'string "all" " " "together" " " "now") "all together now"
	    :test #'equalp)))

    (subtest "Test Mapping Functions"
      (subtest "Test MAP"
	(test-seq-fn
	 ((list (list 1 2 3 4))
	  (empty-list nil)
	  (res '(2 3 4 5)))

	 (test-not-modified
	  ((seq list))
	  (is (map #'1+ seq) res :test #'equalp))

	 ;; Test Empty Sequences
	 (test-not-modified
	  ((seq list)
	   (empty empty-list))

	  ;; Always use unary 1+ in order to signal a condition (and
	  ;; thus fail the tests) if it is called.
	  (is (map #'1+ empty) empty :test #'equalp)
	  (is (map #'1+ seq empty) empty :test #'equalp)
	  (is (map #'1+ empty seq) empty :test #'equalp)))

	(test-seq-fn
	 ((list1 (list 1 2 3 4))
	  (list2 (list 2 3 4 5))
	  (res '(3 5 7 9)))

	 (test-not-modified
	  ((seq1 list1)
	   (seq2 list2))
	  (is (map #'+ seq1 seq2) res :test #'equalp))))

      (subtest "Test NMAP"
	(test-seq-fn
	 ((seq (list 1 2 3 4))
	  (empty nil)
	  (res '(2 3 4 5)))

	 (is (nmap seq #'1+) res :test #'equalp)

	 ;; Test Empty Sequences

	 ;; Always use unary 1+ in order to signal a condition (and
	 ;; thus fail the tests) if it is called.
	 (is (nmap empty #'1+) empty :test #'equalp)
	 (is (nmap seq #'1+ empty) seq :test #'equalp)
	 (is (nmap empty #'1+ seq) empty :test #'equalp))

	(test-seq-fn
	 ((seq1 (list 1 2 3 4))
	  (seq2 (list 2 3 4 5))
	  (res '(3 5 7 9)))

	 (is (nmap seq1 #'+ seq2) res :test #'equalp)))

      (subtest "Test MAP-INTO"
	(test-seq-fn
	 ((out (list 1 2))
	  (seq1 '(2 3))
	  (seq2 '(1 1))
	  (empty nil)
	  (res '(1 2 3 4)))

	 (is (map-into out #'1+ seq1) res :test #'equalp)
	 (is (map-into out #'+ seq1 seq2) res :test #'equalp)

	 ;; Empty Sequences
	 (is (map-into empty #'1+ out) seq1 :test #'equalp)
	 (is (map-into out #'1+ empty) out :test #'equalp)
	 (is (map-into out #'+ empty seq1) out :test #'equalp)))

      (subtest "Test MAP-TO"
	(test-seq-fn
	 ((chars  '(#\h #\e #\l #\l #\o))
	  (seq '(1 2 3 4))
	  (empty nil))

	 (let ((str (map-to 'string #'char-upcase chars)))
	   (is-type str 'string "Result is string")
	   (is str "HELLO"))

	 (is (map-to 'list #'1+ seq) '(2 3 4 5))
	 (is (map-to 'vector #'+ seq seq) #(2 4 6 8) :test #'equalp)
	 (is (map-to 'list-wrapper #'1+ seq) (list-wrap 2 3 4 5) :test #'equalp)

	 ;; Empty Sequences

	 ;; Always use unary 1+ in order to signal a condition (and
	 ;; thus fail the tests) if it is called.
	 (is (map-to 'vector #'1+ empty) #() :test #'equalp)
	 (is (map-to 'list #'1+ seq empty) nil :test #'equalp)

	 (is-error (map-to 'not-a-sequence-type #'1+ seq) condition)))

      (subtest "Test FOREACH"
	(test-seq-fn
	 ((seq '(1 2 3 4))
	  (empty nil))

	 (let ((collector (make-collector (list-wrap))))
	   (foreach
	    (lambda (x)
	      (accumulate collector x))
	    seq)

	   (is (collector-sequence collector) (list-wrap 1 2 3 4) :test #'equalp))

	 (let ((collector (make-collector (list-wrap))))
	   (foreach
	    (lambda (x y)
	      (accumulate collector (+ x y)))
	    seq seq)

	   (is (collector-sequence collector) (list-wrap 2 4 6 8) :test #'equalp))

	 ;; Empty Sequences
	 (block test-empty
	   (flet ((fail-test (&rest args)
		    (declare (ignore args))
		    (fail "Unary Function Called.")
		    (return-from test-empty nil)))

	     (foreach #'fail-test empty)
	     (foreach #'fail-test seq empty)

	     (pass "FOREACH called with empty sequences"))))))))

(finalize)
