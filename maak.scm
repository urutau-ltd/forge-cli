(define-module (maak)
  #:declarative? #t
  #:use-module (maak maak)
  #:use-module (ice-9 ftw))

(define project-name
  'forge-cli)

(define (test)
  "Run the test suite"
  ($ '("zig" "build" "test")
     #:verbose? #t))

(define (build)
  "Build the project executable"
  ($ '("zig" "build" "-Doptimize=ReleaseSafe")
     #:verbose? #t))

(define (build-test)
  "Test if the project compiles"
  ($ '("zig" "build" "run")
     #:verbose? #t))

(define (clean)
  "Cleanup build artifacts"
  ($ '("rm" "-rf" ".zig-cache" "zig-out")
     #:verbose? #t))

(define (default)
  (build-test))
