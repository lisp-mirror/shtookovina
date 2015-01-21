;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; -*-
;;;
;;; This module defines functions to read and parse Shtooka database. It
;;; also provides functions to get file name of relevant audio recording
;;; according to given word of interest.
;;;
;;; Copyright (c) 2015 Mark Karpov
;;;
;;; Shtookovina is free software: you can redistribute it and/or modify it
;;; under the terms of the GNU General Public License as published by the
;;; Free Software Foundation, either version 3 of the License, or (at your
;;; option) any later version.
;;;
;;; Shtookovina is distributed in the hope that it will be useful, but
;;; WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
;;; Public License for more details.
;;;
;;; You should have received a copy of the GNU General Public License along
;;; with this program. If not, see <http://www.gnu.org/licenses/>.

(in-package #:shtookovina)

(defvar *shtooka-dirs* nil
  "List of paths to directories that contain data bases of audio
recordings.")

(defparameter *shtooka-index* "index.tags.txt"
  "Name of index file in directory that contains Shtooka database.")

(defvar *audio-index* nil
  "This hash table allows to lookup names of audio files relevant to given
word (not necessary in its base form). INIT-SHTOOKA-DB reads Shtooka
database index and fills this hash table.")

(defvar *text-index* nil
  "This hash table allows to lookup text corresponding to given filename in
data base.")

(defvar *auxiliary-index* nil
  "Hash table that contains only auxiliary words. It's used when normal
search fails and before invocation of :FAILED-PLAY or :SUCCESSFUL-PLAY.")

(defparameter *target-tag* "SWAC_TEXT"
  "This tag will be used to fill out *AUDIO-INDEX*.")

(defparameter *uniqueness-threshold* 1/250
  "A word is considered auxiliary in current language, if it appears in
this (or greater) share of all texts in data base. Auxiliary words are
deleted from *AUDIO-INDEX* to speed up playback.")

(defun extract-words (str)
  "Split text into words, according to Sthookovina concept of word."
  (remove-duplicates
   (remove-if #'emptyp
              (split-sequence-if-not #'alpha-char-p str))
   :test #'string-equal))

(defun init-shtooka-db (&aux (total 0))
  "Generate contents of *AUDIO-INDEX*, *TEXT-INDEX*, and
*AUXILIARY-INDEX*. This function must be called before first call of
PLAY-ITEM. Invalid directories will be ignored."
  (labels ((headerp (str)
             (and (not (emptyp str))
                  (char= (first-elt str) #\[)
                  (char= (last-elt str) #\])
                  (subseq str 1 (1- (length str)))))
           (parse-tag (str)
             (when (find #\= str :test #'char=)
               (split-sequence #\= str)))
           (find-text (key str)
             (when (string= key (gethash str *text-index*))
               str))
           (get-index (dir)
             (ensure-list (probe-file (merge-pathnames dir *shtooka-index*))))
           (parse-db (index-file actual-dir)
             (with-open-file (stream index-file :direction :input)
               (do ((line (read-line stream nil)
                          (read-line stream nil))
                    actual-file
                    target-tag)
                   ((null line))
                 (aif (headerp line)
                      (progn
                        (when (and actual-file target-tag)
                          (dolist (item (extract-words target-tag))
                            (push actual-file
                                  (gethash item *audio-index*)))
                          (setf (gethash actual-file *text-index*)
                                target-tag))
                        (setf actual-file (namestring
                                           (merge-pathnames actual-dir it))
                              total       (1+ total)
                              target-tag  nil))
                      (awhen (parse-tag line)
                        (destructuring-bind (k v) it
                          (when (string= *target-tag* k)
                            (setf target-tag v)))))))))
    (when *shtooka-dirs*
      (setf *audio-index*     (make-hash-table :test #'equalp)
            *text-index*      (make-hash-table :test #'equal)
            *auxiliary-index* (make-hash-table :test #'equalp))
      (dolist (index-file (mapcan #'get-index
                                  (ensure-list *shtooka-dirs*)))
        (parse-db index-file
                  (make-pathname :directory (pathname-directory index-file))))
      (maphash (lambda (key value)
                 (when (>= (length value)
                           (* *uniqueness-threshold* total))
                   (remhash key *audio-index*)
                   (awhen (find key value :test #'find-text)
                     (setf (gethash key *auxiliary-index*) it))))
               *audio-index*))))

(defun play-item (text)
  "Invokes :PLAY-ITEM hook with file name of audio file corresponding to
given TEXT as first argument. TEXT may be word or phrase. If data base
contains several files corresponding to the same text, one of them will be
randomly selected. This function calls :SUCCESSFUL-PLAY hook when the system
can find relevant recording and :FAILED-PLAY on failure (blocking calls,
given text is passed as argument)."
  (flet ((quote-filename (filename)
           (if (find #\space filename :test #'char=)
               (format nil "\"~a\"" filename)
               filename))
         (count-items (items)
           (let ((counts (make-hash-table)))
             (hash-table-alist
              (dolist (item items counts)
                (if (gethash item counts)
                    (incf (gethash item counts))
                    (setf (gethash item counts) 1)))))))
    (or
     (when-let* ((words (extract-words text))
                 (counts (count-items
                          (or (mappend (lambda (x)
                                         (gethash x *audio-index*))
                                       words)
                              (ensure-list
                               (gethash (car words) *auxiliary-index*)))))
                 (extremum (cdr (extremum counts #'> :key #'cdr)))
                 (pretenders (remove-if (curry #'> extremum)
                                        counts
                                        :key #'cdr))
                 (selected (car (random-elt pretenders))))
       (perform-hook :play-item
                     :args (quote-filename selected)
                     :in-thread t
                     :put-into-shell t)
       (perform-hook :successful-play
                     :args (gethash selected *text-index*))
       t)
     (perform-hook :failed-play
                   :args text))))

;;; --- testing ---

(setf *shtooka-dirs*
      '("/home/mark/Downloads/eng-balm-emmanuel/"
        "/home/mark/Downloads/eng-balm-judith/"
        "/home/mark/Downloads/eng-balm-judith-proverbs/"
        "/home/mark/Downloads/eng-balm-verbs/"
        "/home/mark/Downloads/eng-wcp-us/"
        "/home/mark/Downloads/eng-wims-mary/"
        "/home/mark/Downloads/eng-wims-mary-conversation/"
        "/home/mark/Downloads/eng-wims-mary-num/"))

;; (setf *shtooka-dirs*
;;       '("/home/mark/Downloads/fra-balm-conjug/"
;;         "/home/mark/Downloads/fra-balm-flora-expr/"
;;         "/home/mark/Downloads/fra-balm-flora-num/"
;;         "/home/mark/Downloads/fra-balm-frank/"
;;         "/home/mark/Downlaods/fra-balm-tnitot/"
;;         "/home/mark/Downloads/fra-balm-voc/"
;;         "/home/mark/Downloads/fra-nallet-camille/"
;;         "/home/mark/Downloads/fra-nallet-caroline/"
;;         "/home/mark/Downlaods/fra-nallet-christian/"
;;         "/home/mark/Downloads/fra-nallet-denise/"
;;         "/home/mark/Downloads/fra-nallet-marie/"
;;         "/home/mark/Downloads/fra-nallet-nicolas/"
;;         "/home/mark/Downloads/fra-nallet-odile/"
;;         "/home/mark/Downloads/fra-wims-lettres fra-wims-voc/"))

(register-hook :play-item
               (lambda (x)
                 (format nil "flac -cd ~a | aplay" x)))

(register-hook :successful-play
               (lambda (x)
                 (format t "proposed recording: \"~a\"~%" x)))

(register-hook :failed-play
               (lambda (x)
                 (format t "cannot find audio for \"~a\"~%" x)))