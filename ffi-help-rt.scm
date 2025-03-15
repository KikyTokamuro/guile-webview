;;; system/ffi-help-rt.scm - NYACC's FFI help runtime

;; Copyright (C) 2016-2019,2022-2024 Matthew Wette
;;
;; This library is free software; you can redistribute it and/or
;; modify it under the terms of the GNU Lesser General Public
;; License as published by the Free Software Foundation; either
;; version 3 of the License, or (at your option) any later version.
;;
;; This library is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; Lesser General Public License for more details.
;;
;; You should have received a copy of the GNU Lesser General Public License
;; along with this library; if not, see <http://www.gnu.org/licenses/>

;;; Code:

(define-module (system ffi-help-rt)
  #:export (*ffi-help-version*

            ;; user level routines
            fh-type?
            fh-object? fh-object-val
            fh-object-ref fh-object-set! fh-object-addr
            pointer-to value-at NULL !0

            ;; maybe used outside of modules?
            fh:cast fh-cast bs-addr
            fh:function
            fh:pointer
            ffi-void*
            make-fht

            ;; called from output of the ffi-compiler
            define-fh-pointer-type
            define-fh-type-alias
            define-fh-compound-type
            define-fh-vector-type
            define-fh-function*-type
            fh-ref<=>deref! ref<->deref!
            make-symtab-function
            fh-find-symbol-addr
            fht-wrap fht-unwrap fh-wrap fh-unwrap
            unwrap~fixed unwrap~float
            unwrap~pointer unwrap~array
            make-fctn-param-unwrapper
            fh-link-proc fh-link-extern

            ;; commonly used libc functions
            fopen fclose

            ;; deprecated
            fh-link-bstr ;; => fh-link-extern
            )
  #:use-module (bytestructures guile)
  #:use-module (bytestructures guile ffi)
  #:use-module (rnrs bytevectors)
  #:use-module ((system foreign) #:prefix ffi:)
  #:use-module (srfi srfi-9)
  #:version (1 09 4))

(define *ffi-help-version* "1.09.4")

(use-modules (ice-9 pretty-print))
(define (sferr fmt . args)
  (apply simple-format (current-error-port) fmt args))
(define (pperr exp)
  (pretty-print exp (current-error-port) #:per-line-prefix "  "))

(cond-expand
 (guile-2.2)
 (guile-2
  (define-public intptr_t long)
  (define-public uintptr_t unsigned-long))
 (guile))

(define (fherr fmt . args)
  (apply throw 'ffi-help-error fmt args))

;; The FFI helper uses a base type based on Guile structs and vtables.
;; The base vtable uses these (lambda (obj) ...) fields:
;; 0 unwrap     : convert helper-type object to ffi argument
;; 1 wrap       : convert ffi object to helper-type object
;; 2 pointer-to : (pointer-to <foo_t-obj>) => <foo_t*-obj>
;; 3 value-at   : (value-at <foo_t*-obj>) => <foo_t-obj>
;; The C-based (child) types will add a slot for the object value.
(define ffi-helper-type
  (make-vtable
   (string-append standard-vtable-fields "pwpwpwpw")
   (lambda (v p)
     (display "#<ffi-helper-type>" p))))
(define unwrap-ix 0)
(define wrap-ix 1)
(define pointer-to-ix 2)
(define value-at-ix 3)

;; @deffn {Syntax} make-fh-type name unwrap pointer-to value-at printer
;; We call make-struct here but we are actually making a vtable
;; We should check with struct-vtable?
;; name as symbol
(define* (make-fht name unwrap wrap pointer-to value-at printer)
  (let* ((ty (make-struct/no-tail
              ffi-helper-type
              (make-struct-layout "pw") ;; 1 slot for value
              printer
              (or unwrap (lambda (obj) (fherr "no unwrapper")))
              (or wrap (lambda (obj) (fherr "no wrapper")))
              (or pointer-to (lambda (obj) (ffi:bytevector->pointer
                                            (bytestructure-bytevector
                                             (fh-object-val obj)))))
              (or value-at (lambda (obj) (bytestructure-ref
                                          (fh-object-val obj) '*)))))
         (vt (struct-vtable ty)))
    (set-struct-vtable-name! vt name)
    ty))

;; @deffn {Procedure} fh-type? type
;; This predicate tests for FH types.
;; @end deffn
(define (fh-type? type)
  (and (struct? type)
       (struct-vtable? type)
       (eq? (struct-vtable type) ffi-helper-type)))

;; return methods from the type
;; do not export, but check
(define (fht-unwrap type)
  (struct-ref type (+ vtable-offset-user unwrap-ix)))
(define (fht-wrap type)
  (struct-ref type (+ vtable-offset-user wrap-ix)))
(define (fht-pointer-to type)
  (struct-ref type (+ vtable-offset-user pointer-to-ix)))
(define (fht-value-at type)
  (struct-ref type (+ vtable-offset-user value-at-ix)))
(define (fht-printer type)
  (struct-ref type vtable-index-printer))

;; execute the type method on the object
(define (fh-unwrap type obj)
  ((fht-unwrap type) obj))
(define (fh-wrap type val)
  ((fht-wrap type) val))

;; Right now this returns a ffi pointer.
;; TODO: add field option so we can do (pointer-to xstr 'vec)
(define (pointer-to obj)
  (cond
   ((fh-object? obj)
    ((fht-pointer-to (struct-vtable obj)) obj))
   ((bytestructure? obj)
    (ffi:bytevector->pointer (bytestructure-bytevector obj)))
   ((bytevector? obj)
    (ffi:bytevector->pointer obj))
   (else
    (fherr "pointer-to: unknown arg type for ~S" obj))))

(define (value-at obj)
  (cond
   ((fh-object? obj)
    ((fht-value-at (struct-vtable obj)) obj))
   ((bytestructure? obj)
    (bytestructure-ref obj '*))
   (else
    (fherr "value-at: unknwn arg type for ~S" obj))))

(define NULL ffi:%null-pointer)
(define (!0 v) (not (zero? v)))
;;(define FALSE 0)
;;(define TRUE 1)

;; === objects ============

;; @deffn {Procedure} fh-object? obj
;; This predicate tests for FH objects, i.e., FFI defined types.
;; @example
;; (define-fh-pointer-type foo_t* foo_t*-desc)
;; (define val (make-foo_t*))
;; (fh-object? val) => #t
;; @end example
;; @end deffn
(define (fh-object? obj)
  (and
   (struct? obj)
   (fh-type? (struct-vtable obj))))

;; @deffn {Procedure} fh-object-type obj
;; return the object type
;; @end deffn
(define (fh-object-type obj)
  (or (fh-object? obj) (fherr "fh-object-type: expecting fh-object arg"))
  (struct-vtable obj))

;; @deffn {Procedure} fh-object-val obj
;; Return the bytestructure object associate with the FH object.
;; If @var{object} is a bytestructure, return that.
;; @deffn
(define (fh-object-val obj)
  (cond
   ((fh-object? obj) (struct-ref obj 0))
   ((bytestructure? obj) obj)
   (else (fherr "fh-object-val: unknown arg type for ~S" obj))))

(define-syntax-rule (fh-object-ref obj arg ...)
  (bytestructure-ref (fh-object-val obj) arg ...))

(define-syntax-rule (fh-object-set! obj arg ...)
  (bytestructure-set! (fh-object-val obj) arg ...))

(define-syntax-rule (fh-object-addr obj arg ...)
  (call-with-values
      (lambda () (bytestructure-unwrap (fh-object-val obj) arg ...))
    (lambda (bv offs desc)
      (+ (ffi:pointer-address (ffi:bytevector->pointer bv)) offs))))

(eval-when (expand load eval)
  (define (gen-id tmpl-id . args)
    (define (stx->str stx)
      (symbol->string (syntax->datum stx)))
    (datum->syntax
     tmpl-id
     (string->symbol
      (apply string-append
             (map (lambda (ss) (if (string? ss) ss (stx->str ss))) args))))))


;; --- typedefs

;; @deffn {Procedure} bs-addr bst
;; Return the raw, numerical address of the bytestruture bytevector data.
;; @end deffn
(define (bs-addr bst)
  (ffi:pointer-address
   (ffi:bytevector->pointer
    (bytestructure-bytevector bst))))

;; type printer for bytestructures-based types
(define (make-bs-printer type)
  (lambda (obj port)
    (display "#<" port)
    (display type port)
    (when #f
      (display " bs-desc:0x" port)
      (display (number->string (ffi:scm->pointer (struct-ref obj 0)) 16) port))
    (when #t
      (display " 0x" port)
      (display (number->string (bs-addr (struct-ref obj 0)) 16) port))
    (display ">" port)))

(define (make-bs*-printer type)
  (lambda (obj port)
    (display "#<" port)
    (display type port)
    (display " 0x" port)
    (display (number->string (bytestructure-ref (struct-ref obj 0)) 16) port)
    (display ">" port)))

(define (make-printer type)
  (lambda (obj port)
    (display "#<" port)
    (display type port)
    (display " 0x" port)
    (display (number->string
              (ffi:pointer-address (ffi:scm->pointer (struct-ref obj 0)))
              16) port)
    (display ">" port)))

;; @deffn {Syntax} define-fh-pointer-type name desc type? make
;; @example
;; (define foo_t*-desc (bs:pointer foo_t-desc))
;; (define-fh-pointer-type foo_t*
;; @end example
;; The second form is based on already defined @code{bs:pointer} descriptor.
;; @end deffn
(define-syntax-rule (define-fh-pointer-type type desc type? make)
  (begin
    (define type
      (make-fht (quote type)
                unwrap~pointer
                (lambda (val)
                  (make (bytestructure desc (ffi:pointer-address val))))
                #f #f
                (make-bs*-printer (quote type))))
    (define (type? obj)
      (and (fh-object? obj) (eq? (struct-vtable obj) type)))
    (define make
      (case-lambda
        ((val)
         (cond
          ((bytestructure? val)
           (make-struct/no-tail type val))
          ((bytevector? val)
           (make-struct/no-tail type (bytestructure desc val)))
          ((number? val)
           (make-struct/no-tail type (bytestructure desc val)))
          ((ffi:pointer? val)
           (make-struct/no-tail type (bytestructure desc
                                                    (ffi:pointer-address val))))
          (else (make-struct/no-tail type val))))
        (() (make 0))))))

;; @deffn {Syntax} fh-ref<=>deref! p-type p-make type make
;; This procedure will ``connect'' the two types so that the procedures
;; @code{pointer-to} and @code{value-at} work.
;; @end deffn
(define (fh-ref<=>deref! p-type p-make type make)
  (if p-make
      (struct-set! type (+ vtable-offset-user 2) ; pointer-to
                   (lambda (obj) (p-make (bs-addr (fh-object-val obj))))))
  (if make
      (struct-set! p-type (+ vtable-offset-user 3) ; value-at
                   (lambda (obj) (make (fh-object-ref obj '*))))))
(define ref<->deref! fh-ref<=>deref!)

;; @deffn {Syntax} define-fh-type-alias alias type
;; set up type alias.  Caller needs to match type? and make
;; @end deffn
(define-syntax-rule (define-fh-type-alias alias type)
  (define alias
    (make-fht (quote alias)
              (fht-wrap type)
              (fht-unwrap type)
              (fht-pointer-to type)
              (fht-value-at type)
              (make-printer (quote alias)))))

;; @deffn {Syntax} define-fh-compound-type type desc type? make
;; Generates an FY aggregate type based on a bytestructure descriptor.
;; @end deffn
(define-syntax-rule (define-fh-compound-type type desc type? make)
  (begin
    (define type
      (make-fht (quote type)
                (lambda (obj)
                  (ffi:bytevector->pointer
                   (bytestructure-bytevector (struct-ref obj 0))))
                (lambda (val)
                  (make-struct/no-tail type (bytestructure desc val)))
                #f #f
                (make-bs-printer (quote type))))
    (define (type? obj)
      (and (fh-object? obj) (eq? (struct-vtable obj) type)))
    (define make
      (case-lambda
        ((arg) (if (bytestructure? arg)
                   (make-struct/no-tail type arg)
                   (make-struct/no-tail type (bytestructure desc arg))))
        (args (make-struct/no-tail type (apply bytestructure desc args)))))))

(define-syntax-rule (define-fh-vector-type type elt-desc type? make)
  (begin
    (define type
      (make-fht (quote type)
                (lambda (obj)
                  (bytestructure-bytevector (struct-ref obj 0)))
                (lambda (val)
                  (cond
                   ((number? val)
                    (let* ((nelt val) (desc (bs:vector nelt elt-desc)))
                      (make-struct/no-tail type (bytestructure desc))))
                   ((bytevector? val)
                    (let* ((nelt (/ (bytevector-length val)
                                    (bytestructure-size elt-desc)))
                           (desc (bs:vector nelt elt-desc)))
                      (make-struct/no-tail type (bytestructure desc))))))
                #f #f
                (make-bs-printer (quote type))))
    (define (type? obj)
      (and (fh-object? obj) (eq? (struct-vtable obj) type)))
    (define make (fht-wrap type))))

;; == bytestructures extensions/workarounds ====================================

;; adopted from code at  https://github.com/TaylanUB covered by GPL3+ and
;; Copyright (C) 2015 Taylan Ulrich BayirliKammer <taylanbayirli@gmail.com>

;;(define-syntax-rule (bytestructure-ref <bytestructure> <index> ...)
;;  (let-values (((bytevector offset descriptor)
;;                (bytestructure-unwrap <bytestructure> <index> ...)))
;;    (bytestructure-primitive-ref bytevector offset descriptor)))

;;(define (reify-bytestructure-ref desc bv

#|
(define-record-type <vector-metadata>
  (make-vector-metadata length element-descriptor)
  vector-metadata?
  (length             vector-metadata-length)
  (element-descriptor vector-metadata-element-descriptor))

(define (fh:vector length descriptor)
  (define element-size (bytestructure-descriptor-size descriptor))
  (define size (* length element-size))
  (define alignment (bytestructure-descriptor-alignment descriptor))
  (define (unwrapper syntax? bytevector offset index)
    (values bytevector
            (if syntax?
                (quasisyntax
                 (+ (unsyntax offset)
                    (* (unsyntax index) (unsyntax element-size))))
                (+ offset (* index element-size)))
            descriptor))
  (define (setter syntax? bytevector offset value)
    (when syntax?
      (error "Writing into vector not supported with macro API."))
    (cond
     ((bytevector? value)
      (bytevector-copy! bytevector offset value 0 size))
     ((vector? value)
      (do ((i 0 (+ i 1))
           (offset offset (+ offset element-size)))
          ((= i (vector-length value)))
        (bytestructure-set!*
         bytevector offset descriptor (vector-ref value i))))
     (else
      (error "Invalid value for writing into vector." value))))
  (define meta (make-vector-metadata length descriptor))
  (make-bytestructure-descriptor size alignment unwrapper #f setter meta))
|#

(define make-pointer-metadata
  (@@ (bytestructures guile pointer) make-pointer-metadata))

(define (fh:pointer %descriptor)
  (define pointer-size (ffi:sizeof '*))
  (define bytevector-address-ref
    (case pointer-size
      ((1) bytevector-u8-ref)
      ((2) bytevector-u16-native-ref)
      ((4) bytevector-u32-native-ref)
      ((8) bytevector-u64-native-ref)))
  (define bytevector-address-set!
    (case pointer-size
      ((1) bytevector-u8-set!)
      ((2) bytevector-u16-native-set!)
      ((4) bytevector-u32-native-set!)
      ((8) bytevector-u64-native-set!)))
  (define (pointer-ref bytevector offset content-size)
    (let ((address (bytevector-address-ref bytevector offset)))
      (if (zero? address)
          (fherr "fh:pointer: tried to dereference null-pointer")
          (ffi:pointer->bytevector (ffi:make-pointer address) content-size))))
  (define (pointer-idx-ref bytevector offset index content-size)
    (let* ((base-address (bytevector-address-ref bytevector offset))
           (address (+ base-address (* index content-size))))
      (if (zero? base-address)
          (fherr "fh:pointer: tried to dereference null-pointer")
          (ffi:pointer->bytevector (ffi:make-pointer address) content-size))))
  (define (pointer-set! bytevector offset value)
    (cond
     ((exact-integer? value)
      (bytevector-address-set! bytevector offset value))
     ((ffi:pointer? value)
      (bytevector-address-set! bytevector offset (ffi:pointer-address value)))
     ((string? value)
      (bytevector-address-set! bytevector offset
                               (ffi:pointer-address
                                (ffi:string->pointer value))))
     ((bytevector? value)
      (bytevector-address-set! bytevector offset
                               (ffi:pointer-address
                                (ffi:bytevector->pointer value))))
     ((bytestructure? value)
      (bytevector-address-set! bytevector offset
                               (ffi:pointer-address
                                (ffi:bytevector->pointer
                                 (bytestructure-bytevector value)))))))
  (define (get-descriptor)
    (if (promise? %descriptor)
        (force %descriptor)
        %descriptor))
  (define size pointer-size)
  (define alignment size)
  (define (unwrapper syntax? bytevector offset index)
    (define (syntax-list id . elements)
      (datum->syntax id (map syntax->datum elements)))
    (let ((descriptor (get-descriptor)))
      (when (eq? 'void descriptor)
        (fherr "fh:pointer: tried to follow void pointer"))
      (let* ((size (bytestructure-descriptor-size descriptor))
             (index-datum (if syntax? (syntax->datum index) index)))
        (cond
         ((eq? '* index-datum)
          (if syntax?
              (values #`(pointer-ref #,bytevector #,offset #,size) 0 descriptor)
              (values (pointer-ref bytevector offset size) 0 descriptor)))
         ((integer? index-datum)
          (if syntax?
              (values #`(pointer-idx-ref #,bytevector #,offset ,index #,size)
                      0 descriptor)
              (values (pointer-idx-ref bytevector offset index-datum size)
                      0 descriptor)))
         (else
          (if syntax?
              (let ((bytevector* #`(pointer-ref #,bytevector #,offset #,size)))
                (bytestructure-unwrap/syntax
                 bytevector* 0 descriptor (syntax-list index index)))
              (let ((bytevector* (pointer-ref bytevector offset size)))
                (bytestructure-unwrap*
                 bytevector* 0 descriptor index))))))))
  (define (getter syntax? bytevector offset)
    (if syntax?
        #`(bytevector-address-ref #,bytevector #,offset)
        (bytevector-address-ref bytevector offset)))
  (define (setter syntax? bytevector offset value)
    (if syntax?
        #`(pointer-set! #,bytevector #,offset #,value)
        (pointer-set! bytevector offset value)))
  (define meta (make-pointer-metadata %descriptor))
  (make-bytestructure-descriptor size alignment unwrapper getter setter meta))

;; @deffn {Procedure} fh:function return-desc param-desc-list
;; @deffnx {Syntax} define-fh-function*-type name desc type? make
;; Generate a descriptor for a function pseudo-type, and then the associated
;; function pointer type.
;; @example
;; (define foo_t*-desc (bs:pointer (delay double (list double))))
;; @end example
;; @end deffn
(define-record-type <function-metadata>
  (make-function-metadata return-descriptor param-descriptor-list attributes)
  function-metadata?
  (return-descriptor function-metadata-return-descriptor)
  (param-descriptor-list function-metadata-param-descriptor-list)
  (attributes function-metadata-attributes))
(export function-metadata?
        function-metadata-return-descriptor
        function-metadata-param-descriptor-list)

(define (pointer->procedure/varargs return-ffi pointer param-ffi-list)
  (define (arg->ffi arg)
    (cond
     ((bytestructure? arg)
      (bytestructure-descriptor->ffi-descriptor
       (bytestructure-descriptor arg)))
     ((and (pair? arg) (bytestructure-descriptor? (car arg)))
      (bytestructure-descriptor->ffi-descriptor (car arg)))
     ((pair? arg) (car arg))
     (else (fherr "poniter->procedure/varargs: unknown arg type for ~S" arg))))
  (define (arg->val arg)
    (cond
     ((bytestructure? arg) (bytestructure-ref arg))
     ((and (pair? arg) (bytestructure? (cdr arg)))
      (bytestructure-ref (cdr arg)))
     ((pair? arg) (cdr arg))
     (else arg)))
  (define (arg-list->ffi-list param-list arg-list)
    (let loop ((param-l param-list) (argl arg-list))
      (cond
       ((pair? param-l) (cons (car param-l) (loop (cdr param-l) (cdr argl))))
       ((pair? argl) (cons (arg->ffi (car argl)) (loop param-l (cdr argl))))
       (else '()))))
  (lambda args
    (let ((ffi-l (arg-list->ffi-list param-ffi-list args))
          (arg-l (map arg->val args)))
      ;;(sferr "return=~S  params=~S\n" return-ffi ffi-l)
      (apply (ffi:pointer->procedure return-ffi pointer ffi-l) arg-l))))

;; @deffn {Procedure} fh:function return-desc param-desc-list
;; @deffnx {Syntax} define-fh-function*-type name desc type? make
;; Generate a descriptor for a function pseudo-type, and then the associated
;; function pointer type.   If the last element of @var{param-desc-list} is
;; @code{'...} the function is specified as variadic.
;; @example
;; (define foo_t*-desc (bs:pointer (delay (fh:function double (list double)))))
;; @end example
;; @end deffn
(define (fh:function %return-desc %param-desc-list)
  (define (get-return-ffi syntax?)
    (when syntax?
      (throw 'ffi-help-error "fh:function syntax not supported"))
    %return-desc)
  (define (get-param-ffi-list syntax?)
    (let loop ((params %param-desc-list))
      (cond
       ((null? params) '())
       ((pair? (car params)) (cons (cadar params) (loop (cdr params))))
       ((eq? '... (car params)) '())
       (else (cons (car params) (loop (cdr params)))))))
  (define size (ffi:sizeof '*))
  (define alignment size)
  (define attributes
    (let loop ((param-l %param-desc-list))
      (cond ((null? param-l) '())
            ((eq? '... (car param-l)) '(varargs))
            (else (loop (cdr param-l))))))
  (define (getter syntax? bytevector offset) ; assumes zero offset!
    (when syntax?
      (throw 'ffi-help-error "fh:function syntax not supported"))
    (unless (zero? offset)
      (throw 'ffi-help-error "fh:function getter called with non-zero offset"))
    (if (memq 'varargs attributes)
        (pointer->procedure/varargs
         (get-return-ffi #f)
         (ffi:bytevector->pointer bytevector)
         (get-param-ffi-list #f))
        (ffi:pointer->procedure
         (get-return-ffi #f)
         (ffi:bytevector->pointer bytevector)
         (get-param-ffi-list #f))))
  (define meta
    (make-function-metadata %return-desc %param-desc-list attributes))
  (make-bytestructure-descriptor size alignment #f getter #f meta))

;; =============================================================================

(define (bs-desc->ffi-desc bs-desc)
  (cond
   ((bytestructure-descriptor? bs-desc)
    (bytestructure-descriptor->ffi-descriptor bs-desc))
   ((eq? bs-desc 'void) ffi:void)
   (else (fherr "bs-desc->ffi-desc: unknown type for ~S" bs-desc))))

;; given a fh:function return pair: (return-type . arg-list)
(define (fh-function*-signature desc)
  (let* ((meta (bytestructure-descriptor-metadata desc))
         (desc (pointer-metadata-content-descriptor meta))
         (desc (if (promise? desc) (force desc) desc))
         (meta (bytestructure-descriptor-metadata desc))
         (bs-rt (function-metadata-return-descriptor meta))
         (ffi-rt (bs-desc->ffi-desc bs-rt))
         (bs-al (function-metadata-param-descriptor-list meta))
         (ffi-bs-al (map bs-desc->ffi-desc bs-al)))
    (cons ffi-rt ffi-bs-al)))
(define fs-function*-signature fh-function*-signature)

;; @deffn {Syntax} define-fh-function*-type type desc type? make
;; document this
;; @end deffn
(define-syntax define-fh-function*-type
  (syntax-rules ()
    ((_ type desc type? make)
     (begin
       (define type
         (make-fht
          (quote type)
          ;; unwrap:
          (lambda (obj)
            (cond
             ((procedure? obj)          ; a lambda
              (let* ((sig (fh-function*-signature desc)))
                (ffi:procedure->pointer (car sig) obj (cdr sig))))
             ((and (pair? obj) (fh-type? (car obj))) ; fh-cast
              (unwrap~pointer (cdr obj)))
             (else
              (unwrap~pointer obj))))
          ;; wrap:
          (lambda (val) (make (bytestructure desc (ffi:pointer-address val))))
          ;; pointer-to:
          #f
          ;; value-at:
          (lambda (obj) (fh-object-ref obj '*))
          (make-bs*-printer (quote type))))
       (define (type? obj)
         (and (fh-object? obj) (eq? (struct-vtable obj) type)))
       (define make
         (case-lambda
           ((val)
            (cond
             ((number? val) (bytestructure desc val))
             ((ffi:pointer? val) (bytestructure desc (ffi:pointer-address val)))
             ((procedure? val) ;; special case, proceadure not pointer
              (let* ((sig (fh-function*-signature desc)))
                (bytestructure
                 desc
                 (ffi:pointer-address
                  (ffi:procedure->pointer (car sig) val (cdr sig))))))
             (else (fherr "make-function: unknown argument type"))))
           (() (make-struct/no-tail type (bytestructure desc)))))
       (export type type? make)))))

;; @deffn {Procedure} fh:cast type value
;; @deffnx {Procedure} fh-cast type value
;; @example
;; (fh-cast foo_desc_t* 321)
;; (use-modules ((system foreign) #:prefix 'ffi:))
;; (fh-cast ffi:short 321)
;; We might have a procedure that wants be passed as a pointer but
;; @end deffn
;; use cases
;; @itemize
;; @item
;; @example
;; (lambda (x y) #f) => (procedure->pointer void (list '* '*))
;; @end example
;; @end itemize
;; can we now do a vector->pointer
(define (fh:cast type expr)
  (let* ((r-type                        ; resolved type
          (cond
           ((bytestructure-descriptor? type)
            (bytestructure-descriptor->ffi-descriptor type))
           (else type)))
         (r-expr                        ; resolved value
          (cond
           ((equal? r-type ffi-void*)
            (cond
             ((string? expr) (ffi:string->pointer expr))
             ;;((bytestructure? expr)  ...
             (else
              (display "ffi-help-rt: WARNING: bizarre cast\n")
              expr)))
           (else expr))))
    (cons r-type r-expr)))
(define fh-cast fh:cast)

;; --- unwrap / wrap procedures

;; now support for the base types
(define (unwrap~fixed obj)
  (cond
   ((number? obj) obj)
   ((bytestructure? obj) (bytestructure-ref obj))
   ((fh-object? obj) (struct-ref obj 0))
   (else (fherr "unwrap~fixed: type mismatch"))))

(define unwrap~float unwrap~fixed)

;; unwrap-enum has to be inside module

;; FFI wants to see a ffi:pointer type
(define (unwrap~pointer obj)
  (cond
   ((ffi:pointer? obj) obj)
   ((string? obj) (ffi:string->pointer obj))
   ((bytestructure? obj) (ffi:make-pointer (bytestructure-ref obj)))
   ((bytevector? obj) (ffi:bytevector->pointer obj))
   ((fh-object? obj) (unwrap~pointer (struct-ref obj 0)))
   ((exact-integer? obj) (ffi:make-pointer obj))
   (else (fherr "unwrap~pointer: unknown arg type"))))

(define unwrap~array unwrap~pointer)

;; @deffn {Procedure} make-fctn-param-unwrapper ret-t args-t => lambda
;; This procedure will convert an argument,
;; @end deffn
(define (make-fctn-param-unwrapper ret-t args-t)
  (lambda (obj)
    (cond
     ((ffi:pointer? obj) obj)
     ((procedure? obj) (ffi:procedure->pointer ret-t obj args-t))
     (else (fherr "make-fctn-param-unwrapper: unknown type for ~S")))))

;; --- types ---------------------------

;; All other FFI types are variables which as bound to constant expressions.
;; Here we bind '* to a variable to avoid special cases in the code generator.
(define ffi-void* '*)

(define char*-desc (bs:pointer 'void))
(define char*
  (make-fht 'char*
            (lambda (obj) (ffi:pointer->string (fh-object-ref obj)))
            (case-lambda
              ((val)
               (cond
                ((string? val)
                 (bytestructure
                  char*-desc (ffi:pointer-address (ffi:string->pointer val))))
                ((ffi:pointer? val)
                 (bytestructure char*-desc (ffi:pointer-address val)))
                (else
                 (bytestructure char*-desc val))))
              (() (bytestructure char*-desc 0)))
            #f #f
            (make-bs-printer 'char*)))
(define make-char* (fht-wrap char*))
(define char*? (lambda (obj) (eq? (struct-vtable obj) char*)))
(export char*-desc char* char*? make-char*)

(define char**-desc (bs:pointer char*-desc))
(define-fh-pointer-type char** char**-desc char**? make-char**)
(export char**-desc char** char**? make-char**)

(fh-ref<=>deref! char** make-char** char* make-char*)

(define (char*->string obj)
  (ffi:pointer->string (ffi:make-pointer (fh-object-ref obj))))
(export char*->string)

(define fh-void
  (make-fht 'void
            (lambda (obj) 'void)
            (lambda (val) (make-struct/no-tail fh-void val))
            #f #f
            (lambda (obj port) (display "#<fh-void>" port))))
(define fh-void?
  (lambda (obj) (and (struct? obj) (eq? (struct-vtable obj) fh-void))))
(define make-fh-void
  (case-lambda
    (() (make-struct/no-tail fh-void 'void))
    ((val) (make-struct/no-tail fh-void 'void))))
(export fh-void fh-void? make-fh-void)

(define void*-desc (bs:pointer 'void))
(define void*
  (make-fht 'void*
            unwrap~pointer
            (case-lambda
              ((val)
               (cond
                ((string? val)
                 (make-struct/no-tail
                  void* (bytestructure
                         void*-desc (ffi:pointer-address
                                     (ffi:string->pointer val)))))
                ((bytestructure? val)
                 (make-struct/no-tail void* val))
                (else
                 (make-struct/no-tail void* (bytestructure void*-desc val)))))
              (() (make-struct/no-tail void* (bytestructure void*-desc))))
            #f #f
            (lambda (obj port)
              (display "#<void* 0x" port)
              (display (number->string (struct-ref obj 0) 16) port)
              (display ">" port))))
(define make-void* (fht-wrap void*))
(define void*?
  (lambda (obj) (and (struct? obj) (eq? (struct-vtable obj) void*))))
(fh-ref<=>deref! void* make-void* fh-void make-fh-void)
(export void* void*? make-void*)

(define void**-desc (bs:pointer (bs:pointer 'void)))
(define void**
  (make-fht 'void**
            unwrap~pointer
            (case-lambda
              ((val)
               (make-struct/no-tail void** (bytestructure void**-desc val)))
              (()
               (make-struct/no-tail void** (bytestructure void**-desc))))
            #f #f
            (lambda (obj port)
              (display "#<void** 0x" port)
              (display (number->string (struct-ref obj 0) 16) port)
              (display ">" port))))
(define make-void** (fht-wrap void**))
(define void**?
  (lambda (obj) (and (struct? obj) (eq? (struct-vtable obj) void**))))
(fh-ref<=>deref! void** make-void** void* make-void*)
(export void** void**? make-void**)


(define-syntax make-maker
  (syntax-rules ()
    ((_ desc make-bs-obj)
     (define-public make-bs-obj
       (case-lambda
         ((arg) (bytestructure desc arg))
         (() (bytestructure desc)))))))

(make-maker short make-short) (make-maker unsigned-short make-unsigned-short)
(make-maker int make-int) (make-maker unsigned-int make-unsigned-int)
(make-maker long make-long) (make-maker unsigned-long make-unsigned-long)
(make-maker intptr_t make-intptr_t) (make-maker uintptr_t make-uintptr_t)
(make-maker size_t make-size_t) (make-maker ssize_t make-ssize_t)
(make-maker ptrdiff_t make-ptrdiff_t)
(make-maker float make-float) (make-maker double make-double)
(make-maker int8 make-int8) (make-maker uint8 make-uint8)
(make-maker int16 make-int16) (make-maker uint16 make-uint16)
(make-maker int32 make-int32) (make-maker uint32 make-uint32)
(make-maker int64 make-int64) (make-maker uint64 make-uint64)

(define-syntax define-base-pointer-type
  (lambda (x)
    (syntax-case x ()
      ((_ desc)
       (with-syntax ((desc* (gen-id #'desc #'desc "*-desc"))
                     (type* (gen-id #'desc #'desc "*"))
                     (type*? (gen-id #'desc #'desc "*?"))
                     (make* (gen-id #'desc "make-" #'desc "*")))
         #'(begin
             (define desc* (bs:pointer desc))
             (define-fh-pointer-type type* desc* type*? make*)
             (export type* desc* type*? make-type*)))))))

(define-base-pointer-type short) (define-base-pointer-type unsigned-short)
(define-base-pointer-type int) (define-base-pointer-type unsigned-int)
(define-base-pointer-type long) (define-base-pointer-type unsigned-long)
(define-base-pointer-type float) (define-base-pointer-type double)

;; --- other items --------------------

;; @deffn {Procedure} make-symtab-function symbol-value-table prefix
;; generate a symbol table function
;; @example
;; (define-public BUS (make-symtab-function ffi-dbus-symbol-tab))
;; @end example
;; Then use in code as this:
;; @example
;; (define bus (DBUS 'SERVICE_BUS))
;; @end example
;; @noindent
;; which is equivalent to
;; @example
;; (define bus (ffi-dbus-symbol-val 'DBUS_SERVICE_BUS)
;; @end example
;; @end deffn
(define (make-symtab-function symbol-value-table prefix)
  (let* ((cnvt (lambda (pair seed)
                 (let* ((k (car pair)) (v (cdr pair))
                        (n (symbol->string k))
                        (l (string-length prefix)))
                   (if (string-prefix? prefix n)
                       (acons (string->symbol (substring n l)) v seed)
                       seed))))
         (symtab (let loop ((o '()) (i symbol-value-table))
                   (if (null? i) o (loop (cnvt (car i) o) (cdr i))))))
    (lambda (key) (assq-ref symtab key))))


(define (fh-find-symbol-addr name dl-lib-list)
  (let loop ((dll (cons (dynamic-link) dl-lib-list)))
    (cond
     ((null? dll) (throw 'ffi-help-error "function not found"))
     ((catch #t
        (lambda () (dynamic-func name (car dll)))
        (lambda args #f)))
     (else (loop (cdr dll))))))

;; @deffn {Procedure} fh-link-proc return name args dy-lib-list
;; Generate Guile procedure from C library.
;; @end deffn
(define* (fh-link-proc return name args dl-lib-list)
  ;; Given a list of links (output of @code{(dynamic-link @it{library})}
  ;; try to get the dynamic-func for the provided function.  Usually
  ;; the first dynamic link is @code{(dynamic-link)} and that should work.
  ;; But on some systems we need to find the actual library :(, apparently.
  (let ((dfunc (fh-find-symbol-addr name dl-lib-list)))
    (and dfunc (ffi:pointer->procedure return dfunc args))))

;; @deffn {Procedure} fh-link-extern name desc db-lib-list => bs
;; Generate a bytestructure from the bytes in the library at the var addr.
;; @end deffn
(define* (fh-link-extern name desc dl-lib-list)
  (let* ((addr (fh-find-symbol-addr name dl-lib-list))
         (size (bytestructure-descriptor-size desc)))
    (make-bytestructure (ffi:pointer->bytevector addr size) 0 desc)))


#|
;; @deffn {Procedure} make-cstr-array str-list => bv
;; For C functions that take an argument of the form @code{const char *names[]},
;; this routine will convert a scheme list of strings into an appropriate
;; bytevector which can be passed via @code{unwrap~pointer}.
;; @end deffn
(define (make-cstr-array str-list)
  "- Procedure: make-cstr-array str-list => bv
     For C functions that take an argument of the form 'const char
     *names[]', this routine will convert a scheme list of strings into
     an appropriate bytevector which can be passed via 'unwrap~pointer'."
  (let* ((n (length string-list))
         (addresses (map (compose pointer-address
                                  string->pointer)
                         string-list))
             (bv (make-bytevector (* n (sizeof '*))))
             (bv-set! (case (sizeof '*)
                            ((4) bytevector-u32-native-set!)
                            ((8) bytevector-u64-native-set!))))
    (for-each (lambda (address index)
                (bv-set! bv (* (sizeof '*) index) address))
              addresses (iota n))
    bv))
(export make-cstr-array)
|#

;; === common c functions called

;; @deffn {Procedure} fopen filename mode
;; Call the C fucntion fopen and return a scheme @code{<pointer>} type.
;; @end deffn
(define fopen
  (let ((~fopen (ffi:pointer->procedure
                 '* (dynamic-func "fopen" (dynamic-link)) (list '* '*))))
    (lambda (filename mode)
      (~fopen (ffi:string->pointer filename) (ffi:string->pointer mode)))))

;; @deffn {Procedure} fopen file
;; Call the C fucntion fclose on @var<file>, a @code{<pointer>} type generated
;; by @code{fopen}.
;; @end deffn
(define fclose
  (let ((~fclose (ffi:pointer->procedure
                 ffi:int (dynamic-func "fclose" (dynamic-link)) (list '*))))
    (lambda (file)
      (~fclose file))))

;; === deprecated ==============================================================

(define fh-link-bstr fh-link-extern)

;; --- last line ---
