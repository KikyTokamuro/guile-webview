;;; guile-webview

;; MIT License

;; Copyright (c) 2022-2023 Daniil Arkhangelsky (Kiky Tokamuro)

;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in all
;; copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.

(define-module (webview)
  #:version (0 0 2)
  #:use-module (system ffi-help-rt)
  #:use-module ((system foreign) #:prefix ffi:)
  #:use-module (bytestructures guile)
  #:export (webview-version-t
	    webview-version-t?
	    make-webview-version-t
	    
	    webview-version-t*
	    webview-version-t*?
	    make-webview-version-t*

	    webview-version-info-t
	    webview-version-info-t? 
	    make-webview-version-info-t

	    webview-version-info-t*
	    webview-version-info-t*? 
	    make-webview-version-info-t*
	    
	    webview-t
	    webview-t?
	    make-webview-t

	    webview-create
	    webview-destroy
	    webview-run
	    webview-terminate
	    webview-dispatch
	    webview-get-window
	    webview-set-title
	    webview-set-size
	    webview-navigate
	    webview-set-html
	    webview-init
	    webview-eval
	    webview-bind
	    webview-unbind
	    webview-return
	    webview-version

	    ffi-webview-symbol-val
	    ffi-webview-types))

(define ffi-webview-llibs
  (delay (list (dynamic-link "libwebview"))))

;; struct webview_version_t;
(define webview-version-t-desc
  (bs:struct
    (list `(major ,unsigned-int)
          `(minor ,unsigned-int)
          `(patch ,unsigned-int))))

(define-fh-compound-type
  webview-version-t
  webview-version-t-desc
  webview-version-t?
  make-webview-version-t)

(define webview-version-t*-desc
  (fh:pointer webview-version-t-desc))

(define-fh-pointer-type
  webview-version-t*
  webview-version-t*-desc
  webview-version-t*?
  make-webview-version-t*)

(fh-ref<=>deref!
  webview-version-t*
  make-webview-version-t*
  webview-version-t
  make-webview-version-t)

;; struct webview_version_info_t;
(define webview-version-info-t-desc
  (bs:struct
    (list `(version ,webview-version-t-desc)
          `(version-number ,(bs:vector 32 int8))
          `(pre-release ,(bs:vector 48 int8))
          `(build-metadata ,(bs:vector 48 int8)))))

(define-fh-compound-type
  webview-version-info-t
  webview-version-info-t-desc 
  webview-version-info_t?
  make-webview-version-info-t)

(define webview-version-info-t*-desc
  (fh:pointer webview-version-info-t-desc))

(define-fh-pointer-type
  webview-version-info-t*
  webview-version-info-t*-desc 
  webview-version-info_t*?
  make-webview-version-info-t*)

(fh-ref<=>deref!
  webview-version-info-t*
  make-webview-version-info-t*
  webview-version-info-t
  make-webview-version-info-t)

;; typedef void *webview_t;
(define-public webview-t-desc (fh:pointer 'void))
(define-fh-pointer-type webview-t webview-t-desc webview-t? make-webview-t)

;; extern webview_t webview_create(int debug, void *window);
;; ----
;; Creates a new webview instance. If debug is non-zero - developer tools will
;; be enabled (if the platform supports them). The window parameter can be a
;; pointer to the native window handle. If it's non-null - then child WebView
;; is embedded into the given parent window. Otherwise a new window is created.
;; Depending on the platform, a GtkWindow, NSWindow or HWND pointer can be
;; passed here. Returns null on failure. Creation can fail for various reasons
;; such as when required runtime dependencies are missing or when window creation
;; fails.
(define webview-create
  (let ((~webview-create
          (delay (fh-link-proc
                   ffi-void*
                   "webview_create"
                   (list ffi:int ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (debug window)
      (let ((~debug (unwrap~fixed debug))
            (~window (unwrap~pointer window)))
        ((fht-wrap webview-t)
         ((force ~webview-create) ~debug ~window))))))

;; extern void webview_destroy(webview_t w);
;; ----
;; Destroys a webview and closes the native window.
(define webview-destroy
  (let ((~webview-destroy
          (delay (fh-link-proc
                   ffi:void
                   "webview_destroy"
                   (list ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w)
      (let ((~w ((fht-unwrap webview-t) w)))
        ((force ~webview-destroy) ~w)))))

;; extern void webview_run(webview_t w);
;; ----
;; Runs the main loop until it's terminated.
;; After this function exits - you must destroy the webview.
(define webview-run
  (let ((~webview-run
          (delay (fh-link-proc
                   ffi:void
                   "webview_run"
                   (list ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w)
      (let ((~w ((fht-unwrap webview-t) w)))
        ((force ~webview-run) ~w)))))

;; extern void webview_terminate(webview_t w);
;; ----
;; Stops the main loop. It is safe to call this function from another other background thread.
(define webview-terminate
  (let ((~webview-terminate
          (delay (fh-link-proc
                   ffi:void
                   "webview_terminate"
                   (list ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w)
      (let ((~w ((fht-unwrap webview-t) w)))
        ((force ~webview-terminate) ~w)))))

;; extern void webview_dispatch(webview_t w, void (*fn)(webview_t w, void *arg), void *arg);
;; ----
;; Posts a function to be executed on the main thread.
;; You normally do not need to call this function, unless you want to tweak the native window.
(define webview-dispatch
  (let ((~webview-dispatch
          (delay (fh-link-proc
                   ffi:void
                   "webview_dispatch"
                   (list ffi-void* ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w fn arg)
      (let ((~w ((fht-unwrap webview-t) w))
            (~fn ((make-fctn-param-unwrapper
                    ffi:void
                    (list ffi-void* ffi-void*))
                  fn))
            (~arg (unwrap~pointer arg)))
        ((force ~webview-dispatch) ~w ~fn ~arg)))))

;; extern void *webview_get_window(webview_t w);
;; ----
;; Returns a native window handle pointer. When using a GTK backend the pointer
;; is a GtkWindow pointer, when using a Cocoa backend the pointer is a NSWindow
;; pointer, when using a Win32 backend the pointer is a HWND pointer.
(define webview-get-window
  (let ((~webview-get-window
          (delay (fh-link-proc
                   ffi-void*
                   "webview_get_window"
                   (list ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w)
      (let ((~w ((fht-unwrap webview-t) w)))
        ((force ~webview-get-window) ~w)))))

;; extern void webview_set_title(webview_t w, const char *title);
;; ----
;; Updates the title of the native window. Must be called from the UI thread.
(define webview-set-title
  (let ((~webview-set-title
          (delay (fh-link-proc
                   ffi:void
                   "webview_set_title"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w title)
      (let ((~w ((fht-unwrap webview-t) w))
            (~title (unwrap~pointer title)))
        ((force ~webview-set-title) ~w ~title)))))

;; extern void webview_set_size(webview_t w, int width, int height, int hints);
;; ----
;; Updates the size of the native window. See WEBVIEW-HINT constants.
(define webview-set-size
  (let ((~webview-set-size
          (delay (fh-link-proc
                   ffi:void
                   "webview_set_size"
                   (list ffi-void* ffi:int ffi:int ffi:int)
                   (force ffi-webview-llibs)))))
    (lambda (w width height hints)
      (let ((~w ((fht-unwrap webview-t) w))
            (~width (unwrap~fixed width))
            (~height (unwrap~fixed height))
            (~hints (unwrap~fixed hints)))
        ((force ~webview-set-size)
         ~w
         ~width
         ~height
         ~hints)))))

;; extern void webview_navigate(webview_t w, const char *url);
;; ----
;; Navigates webview to the given URL. URL may be a properly encoded data URI.
(define webview-navigate
  (let ((~webview-navigate
          (delay (fh-link-proc
                   ffi:void
                   "webview_navigate"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w url)
      (let ((~w ((fht-unwrap webview-t) w))
            (~url (unwrap~pointer url)))
        ((force ~webview-navigate) ~w ~url)))))

;; extern void webview_set_html(webview_t w, const char *html);
;; ----
;; Set webview HTML directly.
(define webview-set-html
  (let ((~webview-set-html
          (delay (fh-link-proc
                   ffi:void
                   "webview_set_html"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w html)
      (let ((~w ((fht-unwrap webview-t) w))
            (~html (unwrap~pointer html)))
        ((force ~webview-set-html) ~w ~html)))))

;; extern void webview_init(webview_t w, const char *js);
;; ----
;; Injects JavaScript code at the initialization of the new page. Every time
;; the webview will open a new page - this initialization code will be
;; executed. It is guaranteed that code is executed before window.onload.
(define webview-init
  (let ((~webview-init
          (delay (fh-link-proc
                   ffi:void
                   "webview_init"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w js)
      (let ((~w ((fht-unwrap webview-t) w))
            (~js (unwrap~pointer js)))
        ((force ~webview-init) ~w ~js)))))

;; extern void webview_eval(webview_t w, const char *js);
;; ----
;; Evaluates arbitrary JavaScript code. Evaluation happens asynchronously, also
;; the result of the expression is ignored. Use RPC bindings if you want to
;; receive notifications about the results of the evaluation.
(define webview-eval
  (let ((~webview-eval
          (delay (fh-link-proc
                   ffi:void
                   "webview_eval"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w js)
      (let ((~w ((fht-unwrap webview-t) w))
            (~js (unwrap~pointer js)))
        ((force ~webview-eval) ~w ~js)))))

;; extern void webview_bind(webview_t w, const char *name, void (*fn)(const char *seq, const char *req, void *arg), void *arg);
;; ----
;; Binds a native C callback so that it will appear under the given name as a
;; global JavaScript function. Internally it uses webview_init(). The callback
;; receives a sequential request id, a request string and a user-provided
;; argument pointer. The request string is a JSON array of all the arguments
;; passed to the JavaScript function.
(define webview-bind
  (let ((~webview-bind
          (delay (fh-link-proc
                   ffi:void
                   "webview_bind"
                   (list ffi-void* ffi-void* ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w name fn arg)
      (let ((~w ((fht-unwrap webview-t) w))
            (~name (unwrap~pointer name))
            (~fn ((make-fctn-param-unwrapper
                    ffi:void
                    (list ffi-void* ffi-void* ffi-void*))
                  fn))
            (~arg (unwrap~pointer arg)))
        ((force ~webview-bind) ~w ~name ~fn ~arg)))))

;; extern void webview_unbind(webview_t w, const char *name);
;; ----
;; Removes a native C callback that was previously set by webview_bind.
(define webview-unbind
  (let ((~webview-unbind
          (delay (fh-link-proc
                   ffi:void
                   "webview_unbind"
                   (list ffi-void* ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w name)
      (let ((~w ((fht-unwrap webview-t) w))
            (~name (unwrap~pointer name)))
        ((force ~webview-unbind) ~w ~name)))))

;; extern void webview_return(webview_t w, const char *seq, int status, const char *result);
;; ----
;; Responds to a binding call from the JS side. The ID/sequence number must
;; match the value passed to the binding handler in order to respond to the
;; call and complete the promise on the JS side. A status of zero resolves
;; the promise, and any other value rejects it. The result must either be a
;; valid JSON value or an empty string for the primitive JS value "undefined".
(define webview-return
  (let ((~webview-return
          (delay (fh-link-proc
                   ffi:void
                   "webview_return"
                   (list ffi-void* ffi-void* ffi:int ffi-void*)
                   (force ffi-webview-llibs)))))
    (lambda (w seq status result)
      (let ((~w ((fht-unwrap webview-t) w))
            (~seq (unwrap~pointer seq))
            (~status (unwrap~fixed status))
            (~result (unwrap~pointer result)))
        ((force ~webview-return) ~w ~seq ~status ~result)))))

;; extern const webview_version_info_t *webview_version(void );
;; ----
;; Get the library's version information.
(define webview-version
  (let ((~webview-version
          (delay (fh-link-proc
                   ffi-void*
                   "webview_version"
                   (list)
                   (force ffi-webview-llibs)))))
    (lambda ()
      (let ()
        ((fht-wrap webview-version-info-t*)
         ((force ~webview-version)))))))

;; Access to enum symbols and #define'd constants:
(define ffi-webview-symbol-tab
  '((WEBVIEW-HINT-FIXED . 3)
    (WEBVIEW-HINT-MAX . 2)
    (WEBVIEW-HINT-MIN . 1)
    (WEBVIEW-HINT-NONE . 0)))

(define ffi-webview-symbol-val
  (lambda (k)
    (or (assq-ref ffi-webview-symbol-tab k))))

(define (unwrap-enum obj)
  (cond ((number? obj) obj)
        ((symbol? obj) (ffi-webview-symbol-val obj))
        ((fh-object? obj) (struct-ref obj 0))
        (else (error "type mismatch"))))

(define ffi-webview-types
  '((pointer . "webview_version_t")
    "webview_version_t"
    (pointer . "webview_version_info_t")
    "webview_version_info_t"
    "webview_t"))
