;;; -*- Mode: Lisp; Syntax: ANSI-Common-Lisp; -*-
;;;
;;; This module defines concept of language in Shtookovina. Later we'll be
;;; able to use it to define models of various natural languages.
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

(defvar *language* nil
  "Normally, this variable is bound to instance of LANGUAGE class that
represent current language that user learns.")

(defparameter *default-form-name* ""
  "When no forms specified for lexeme in language definition, this form is
automatically created as single form of the lexeme.")

(defclass language ()
  ((name
    :initarg :name
    :initform "?"
    :accessor name
    :documentation "name of the language")
   (lexemes
    :initarg :lexemes
    :initform (make-hash-table)
    :accessor lexemes
    :documentation "collection of lexemes that define language"))
  (:documentation "class to model natural language"))

(defmethod make-load-form ((self language) &optional env)
  (make-load-form-saving-slots self :environment env))

(defclass lexeme ()
  ((name
    :initarg :name
    :initform "?"
    :accessor name
    :documentation "name of the lexeme")
   (forms
    :initarg :forms
    :initform (make-array 0)
    :accessor forms
    :documentation "vector of lexeme forms"))
  (:documentation "model of natural language lexeme"))

(defmethod make-load-form ((self lexeme) &optional env)
  (make-load-form-saving-slots self :environment env))

(defun lexeme (id name &key ss-forms form-aspects)
  "Return two values: ID (keyword) and lexeme that has name
NAME (string). This lexeme will have 'self-sufficient forms' that supplied
with :SS-FORMS key argument, all others forms will be generated by
concatenation of all possible combinations of 'form aspects' as supplied
with :FORM-ASPECTS keyword. However, order of 'form aspects' will be
preserved."
  (flet ((build-forms (aspects)
           (when aspects
             (apply #'map-product
                    (curry #'concatenate 'string)
                    aspects))))
    (values id
            (make-instance 'lexeme
                           :name name
                           :forms
                           (let ((lst
                                  (aif (append ss-forms
                                               (build-forms form-aspects))
                                       it
                                       (list *default-form-name*))))
                             (make-array (length lst)
                                         :initial-contents lst))))))

(defun set-language (name lexemes)
  "This macro defines model of natural language."
  (flet ((build-lexemes (lexemes)
           (let ((result (make-hash-table)))
             (dolist (item lexemes result)
               (multiple-value-bind (id lexeme)
                   (apply #'lexeme item)
                 (setf (gethash id result) lexeme))))))
    (setf *language*
          (make-instance 'language
                         :name name
                         :lexemes (build-lexemes lexemes)))))

(defun get-lexemes ()
  "Return alist of lexemes (id - name) in the actual language."
  (when *language*
    (let (result)
      (maphash (lambda (k v)
                 (push (cons k (name v)) result))
               (lexemes *language*))
      (nreverse result))))

(defun get-lexeme (lexeme)
  "If lexeme LEXEME exists in the actual language, it is returned. Otherwise
NIL is returned."
  (when *language*
    (gethash lexeme (lexemes *language*))))

(defun get-forms (lexeme)
  "Return list of LEXEME forms or NIL if there is no such lexeme in actual
language."
  (awhen (get-lexeme lexeme)
    (forms it)))

(defun forms-number (lexeme)
  "Returns number of forms that has LEXEME in actual language. If there is
no such lexeme in the language, it returns NIL."
  (awhen (get-lexeme lexeme)
    (length (forms it))))

(defun form-name (lexeme &optional (form 0))
  "Returns name of specified FORM (integer) of LEXEME in actual language. If
there is no such lexeme, returns NIL."
  (awhen (get-lexeme lexeme)
    (aref (forms it) form)))
