;;; maak.scm --- Quixotic build automation, ported from Make to maak
;;; -*- mode: scheme; -*-
;;; SPDX-License-Identifier: GPL-3.0-or-later
;;; Copyright © 2024-2026 Urutau-Ltd <softwarelibre@urutau-ltd.org>
;;;
;;;   , _ ,      _    _            _                     _ _      _
;;;  ( o o )    | |  | |          | |                   | | |    | |
;;; /'` ' `'\   | |  | |_ __ _   _| |_ __ _ _   _ ______| | |_ __| |
;;; |'''''''|   | |  | | '__| | | | __/ _` | | | |______| | __/ _` |
;;; |\\'''//|   | |__| | |  | |_| | || (_| | |_| |      | | || (_| |
;;;    """       \____/|_|   \__,_|\__\__,_|\__,_|      |_|\__\__,_|
;;;
;;; This program is free software: you can redistribute it and/or modify
;;; it under the terms of the  GNU General Public License as published by
;;; the Free Software Foundation, either version 3 of the License, or (at
;;; your option) any later version.
;;;
;;; This program is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
;;; See the GNU General Public License for more details.
;;;

(define-public forge-cli
  (package
    (name "forge-cli")
    (version "nightly")
    (source
     (local-file (dirname (current-filename))
                 #:select? (git-predicate (dirname (current-filename)))))
    (build-system zig-build-system)
    (native-inputs (list zig-0.16))
    (home-page "")
    (synopsis "")
    (description "")
    (license license:gpl3+))

 forge-cli
