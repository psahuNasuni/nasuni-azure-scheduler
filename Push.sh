#!/bin/bash
COMMENT=$1
BRANCH="dev6DocNov6th"
USER="psahuNasuni"

echo "****************** SET - Git Remote ORIGIN  ******************"

git remote set-url origin https://psahuNasuni@github.com/psahuNasuni/nasuni-azure-scheduler.git

echo "****************** STARTED - Git ADD  ******************"
git add .
echo "****************** COMPLETED - Git ADD  ******************"

echo "****************** STARTED - Git COMMIT  ******************"
if [[ "$COMMENT" == "" ]]; then
    DATENOW=`date`
    COMMENT="Code Updated on $DATENOW ."
fi
git commit -m "$COMMENT"
echo "****************** COMPLETED - Git COMMIT ******************"

echo "****************** STARTED - Git PUSH  ******************"
git push origin $BRANCH
echo "****************** COMPLETED - Git PUSH to $BRANCH  ******************"
