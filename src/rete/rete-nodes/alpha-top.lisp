(in-package :exil-rete)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; The alpha part of the rete network peforms matching of WMEs against
;; individual conditions.
;; It consists of top-node, subtop-nodes (one for each template + one for simple
;; facts), test-nodes and memory-nodes
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defclass alpha-node (node) ())

;; slot dataflow-networks holds hash table of network top nodes in alpha memory.
;; for each template there is a dataflow network (accessible through
;; its template name) and one network is for simple-facts
;; slot simple-fact-key holds dataflow-networks hash-key for simeple-facts
;; if there was some constant name for this, it wouldn't be possible to create
;; template of such name
(defclass alpha-top-node (alpha-node)
  ((dataflow-networks :accessor networks :initform (make-hash-table))
   (simple-fact-key :accessor simple-fact-key
                    :initform (gensym "simple-fact")))
  (:documentation "Top node of the alpha-part of rete network, stores one
                   dataflow network for each template and one for simple-facts"))

(defgeneric network (node &optional tmpl-name)
  (:documentation "returns dataflow network for given template name
                   or simple-fact network if template name omitted"))
(defgeneric (setf network) (value node &optional tmpl-name)
  (:documentation "sets dataflow network for given template name
                   or simple-fact network by default"))
(defgeneric initialize-network (node &optional tmpl-name)
  (:documentation "creates new dataflow network for given template name
                   or simple-fact network by default"))
(defgeneric ensure-network (node &optional tmpl-name)
  (:documentation "either returns dataflow network for given template name
                   (or simple-fact network by default) if it exists or
                   initializes a new one and returns it"))
(defgeneric network-key (node wme)
  (:documentation "returns dataflow-networks hash-key for given wme
                   i.e. either its tmpl-name or simple-fact-key"))

(defmethod network ((node alpha-top-node)
                    &optional (tmpl-name (simple-fact-key node)))
  (gethash tmpl-name (networks node)))

(defmethod (setf network) (value (node alpha-top-node)
                           &optional (tmpl-name (simple-fact-key node)))
  (setf (gethash tmpl-name (networks node)) value))

(defmethod initialize-network ((node alpha-top-node)
                               &optional (tmpl-name (simple-fact-key node)))
  (setf (network node tmpl-name)
        (make-instance 'alpha-subtop-node :tmpl-name tmpl-name)))

; called by rete-net-creation
(defmethod ensure-network ((node alpha-top-node)
                           &optional (tmpl-name (simple-fact-key node)))
  (or (network node tmpl-name)
      (initialize-network node tmpl-name)))

(defmethod network-key ((node alpha-top-node) (wme fact))
  (typecase wme
    (simple-fact (simple-fact-key node))
    (template-fact (name (template wme)))))

;; called by add-wme
;; activates appropriate subtop node
(defmethod activate ((node alpha-top-node) (wme fact))
  (activate (ensure-network node (network-key node wme)) wme))

;; called by remove-wme
;; inactivates appropriate subtop node
(defmethod inactivate ((node alpha-top-node) (wme fact))
  (inactivate (ensure-network node (network-key node wme)) wme))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; after alpha-top-node selects the right dataflow network according to fact type
;; and (in case of template-fact) template name, it activates the appropriate
;; subtop node
;; the subtop-nodes are created, when condition of that template (or simple)
;; appears for the first time in some newly added rule
(defclass alpha-subtop-node (alpha-node)
  ;; stored for debug purposes
  ((tmpl-name :accessor tmpl-name :initarg :tmpl-name)))

(defmethod activate ((node alpha-subtop-node) (wme fact))
  (activate-children node wme))
