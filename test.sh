#!/bin/bash
colordiff -u <(./lexer "$1") <(reflexer "$1")
