(in-package :exil)

; private
(defparameter *clips-mode* nil)

; public
(defun set-clips-mode (val)
  (setf *clips-mode* val))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; application macros

(defun nonclips-slot-spec-p (slot-spec)
  (and (symbolp (first slot-spec))
       (or (null (rest slot-spec))
	   (keywordp (second slot-spec)))))

(defun clips-slot-spec-p (slot-spec)
  (and (weak-symbol-equal-p (first slot-spec) 'slot))
       (symbolp (second slot-spec))
       (listp (nthcdr 2 slot-spec)))

(defun slot-spec-p (slot-spec)
  (or (nonclips-slot-spec-p slot-spec)
      (clips-slot-spec-p slot-spec)))

(defun clips-slot->slot-des% (slot-spec)
  (destructuring-bind (slot slot-name &optional (modifiers nil)) slot-spec
    (declare (ignore slot))
    `(,slot-name . (:default ,(second modifiers)))))

(defun nonclips-slot->slot-des% (slot-spec)
  (destructuring-bind (slot-name &key (default nil)) slot-spec
    `(,slot-name . (:default ,default))))

(defun slot->slot-designator% (slot-spec)
  (cond 
    ((nonclips-slot-spec-p slot-spec) (nonclips-slot->slot-des% slot-spec))
    ((clips-slot-spec-p slot-spec) (clips-slot->slot-des% slot-spec))
    (t (error "~A not a valid template slot specifier~%" slot-spec))))

(defun slots->slot-designators% (slots)
  (loop for slot in (to-list-of-lists slots)
     collect (slot->slot-designator% slot)))

(defmacro deftemplate (name &body slots)
  (let ((template (gensym "template")))
    `(let ((,template
	    (make-template ',name
			   ',(slots->slot-designators% slots))))
       (add-template ,template))))

(defun facts (&optional (start-index 1) (end-index (length (exil-env:facts)))
			(at-most end-index))
  (let ((facts (exil-env:facts)))
    (loop for i from (1- start-index) to (min (1- end-index) (+ start-index at-most -1))
       collect (nth i facts))))

(defun assert% (fact-spec)
  (add-fact (make-fact fact-spec)))

(defmacro assert (&rest fact-specs)
  "Add fact into working memory"
  (let ((fact-spec (gensym "fact-spec")))
    `(dolist (,fact-spec ',fact-specs)
       (assert% ,fact-spec))))

(defun retract% (fact-specs)
  (let (facts-to-remove)
    (dolist (fact-spec fact-specs)
      (typecase fact-spec
	(list (pushnew (make-fact fact-spec) facts-to-remove))
	(integer (pushnew (nth (1- fact-spec) (facts)) facts-to-remove))
	(t (error "Type ~A not supported by retract" (type-of fact-spec)))))
    (dolist (fact facts-to-remove)
      (rem-fact fact))))

; retract supports either full fact specification e.g. (retract (is-animal duck))
; or number indices (starting with 1) for clips compatitibity.
; It can't support * to retract all facts as clips does, cause this symbol has
; a special meaning in lisp. retract-all does this instead.
(defmacro retract (&rest fact-specs)
  "Remove fact from working memory"
  `(retract% ',fact-specs))

(defun retract-all ()
  (reset-facts))

(defun nonclips-mod-list-p (mod-list)
  (plistp mod-list))

(defun clips-mod-list-p (mod-list)
  (alistp mod-list))

(defun clips->nonclips-mod-list (mod-list)
  (loop for (slot-name . new-val) in mod-list
     append (list (to-keyword slot-name) new-val)))

(defun to-mod-spec-list (mod-list)
  (cond
    ((nonclips-mod-list-p mod-list) mod-list)
    ((clips-mod-list-p mod-list) (clips->nonclips-mod-list mod-list))
    (t (error "~A not a valid modify specifier" mod-list))))

(defmethod modify% ((fact-spec list) mod-list)
  (let ((mod-fact (make-fact fact-spec)))
    (unless (typep mod-fact 'template-fact)
      (error "modify: ~A is not a template fact specification" fact-spec))
    (modify-fact mod-fact (to-mod-spec-list mod-list))))

(defmethod modify% ((fact-spec integer) mod-list)
  (let ((mod-fact (nth (1- fact-spec) (facts))))
    (unless (typep mod-fact 'template-fact)
      (error "modify: ~A is not a template fact" mod-fact)) 
    (modify-fact mod-fact mod-list)))

(defmacro modify (fact-spec &rest mod-list)
  "Replace old-fact by new-fact"
  (typecase fact-spec
    (list `(modify% ',fact-spec ',mod-list))
    (integer `(modify% ,fact-spec ',mod-list))
    (t (error "modify doesn't support fact specification of type ~A"
	      (type-of fact-spec)))))

(defun clear ()
  "Delete all facts"
  (reset-environment))

(defmacro deffacts (name &body fact-descriptions)
  "Create group of facts to be asserted after (reset)"
  (if (stringp (first fact-descriptions)) (pop fact-descriptions))
  `(add-fact-group ',name ',fact-descriptions))

(defmacro undeffacts (name)
  "Delete fact group"
  `(rem-fact-group ',name))

(defun assert-group% (fact-descriptions)
  (dolist (desc fact-descriptions)
    (assert% desc)))

(defun reset ()
  "Clear all facts and add all fact groups"
  (clear)
  (dolist (group (fact-groups))
    (assert-group% (cdr group))))

(defun my-position (atom list)
  (position atom list))

; extracts actual conditions from rule conditions list, which can also
; include ?fact <- <condition> statements
; returns list of pairs (<condition> , <match-variable>)
; TODO: add some tests - when ?fact <- not followed by condition definition
; this will just piss itself
(defun extract-conditions% (cond-list)
  (loop for i = 0 then (1+ i)
     for cond = (first cond-list) then (nth i cond-list)
     while (< i (length cond-list))
     if (listp cond)
       collect (cons cond nil)
     else
       collect (cons (nth (+ i 2) cond-list) cond) and
       do (incf i 2)))

;; DODELAT KONTROLU, ZDA SE VSECHNY PROMENNE V RHS VYSKYTUJI V LHS
(defmacro defrule (name &body rule)
  "Define rule"
  (when (stringp (first rule))
    (pop rule)) ;; ignore the clips rule header
  (let* ((=>-position (position '=> rule :test #'weak-symbol-equal-p))
	 (conditions (extract-conditions% (subseq rule 0 =>-position)))
	 (activations (subseq rule (1+ =>-position)))
	 (rule-symbol (gensym "rule")))
    (cl:assert =>-position ()
	    "rule definition must include =>")
    `(let ((,rule-symbol
	    (make-rule ',name
		       (mapcar (lambda (condition)
				 (make-pattern (car condition) :match-var (cdr condition)))
			       ',conditions)
		       ',activations)))
       (add-rule ,rule-symbol))))

(defun ppdefrule% (name)
  (let ((rule (find-rule name)))
    (format t "(defrule ~A~{~%  ~A~}~%  =>~{~%  ~S~})"
	    name (conditions rule) (activations rule))))

(defmacro ppdefrule (name)
  `(ppdefrule% ',name))

(defmacro undefrule (name)
  "Undefine rule"
  (let ((rule (gensym "rule")))
    `(let ((,rule (find-rule ',name)))
       (when ,rule (rem-rule ,rule)))))

(defmacro defstrategy (name function)
  "Define strategy"
  `(add-strategy ',name ,function))

(defmacro setstrategy (name)
  "Set strategy to use"
  `(set-strategy ',name))

(defun step ()
  "Run inference engine for one turn"
  (when (agenda)
    (activate-rule (select-activation))
    t))

(defvar *exil-running* nil)

(defun halt ()
  "Stop the inference engine"
  (format t "Halting~%")
  (setf *exil-running* nil))

(defun run ()
  "Run the infenece engine"
  (setf *exil-running* t)
  (loop while (and *exil-running* (step))))

(defmacro watch (watcher)
  "Watch selected item (facts, rules, activations)"
  `(progn (if (weak-symbol-equal-p ',watcher 'all)
	      (watch-all)
	      (set-watcher ',watcher))
	  nil))

(defmacro unwatch (watcher)
  "Unwatch selected item"
  `(progn (if (weak-symbol-equal-p ',watcher 'all)
	      (unwatch-all)
	      (unset-watcher ',watcher))
	  nil))

