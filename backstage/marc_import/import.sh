#!/usr/bin/bash
#
# Copyright (C) 2026 Georgia Public Library Service
# Chris Sharp <csharp@georgialibraries.org>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# A program for automating Backstage record import.

# USAGE NOTE: this script expects a script name 'eg_staged_bib_overlay'
# to exist in the current working directory.  This script is from
# the Equinox Open Library Initiative's migration tools repository at
# https://github.com/EquinoxOpenLibraryInitiative/migration-tools/
# 
# In our case, we create a symbolic link to the cloned git repository, e.g.
# `git clone https://github.com/EquinoxOpenLibraryInitiative/migration-tools.git` in 
# the /home of our user, then `ln -s /home/user/migration-tools/eg_staged_bib_overlay eg_staged_bib_overlay`
#
# Documentation for the overlay script can be accessed with `./eg_staged_bib_overlay --help`.
# 
# This script also assumes the presence of a ~/.pg_service.conf and a corresponding ~/.pgpass.
# See https://www.postgresql.org/docs/current/libpq-pgservice.html and
# https://www.postgresql.org/docs/current/libpq-pgpass.html for more information.

WORK_DIR=$(pwd)
IN_DIR="In"
DONE_DIR="Done"
# eg_staged_bib_overlay requires bib and authority schemas to already exist in the database
BIB_SCHEMA="bib_load"
AUTH_SCHEMA="auth_load"
SCRIPT="$WORK_DIR/eg_staged_bib_overlay"
DB_NAME="mydbname"
DB_HOST="mydbhost"
DB_USER="mydbuser"
FILES=""
# BSLW creates two files for us, the new authorities and current cataloging files.
# New authorities files are named with an example prefix, year/month in YYMM format,
# and an N and contain authority records in MARC21 format (zipped).  The current cataloging files
# are similarly named, but end in C.RECORDS, and contain bibliographic records in MARC21 format.
FILEDATE="$(date +%y%m)"
BFILE="EXAMPLE${FILEDATE}C.RECORDS.zip"
AFILE="EXAMPLE${FILEDATE}N.zip"
FTP_HOST="ftp.example.com"
FTP_USER="myftpuser"
FTP_PASS="myftppass"
FTP_PATH="myftpremotepath"

FTPFiles () {
    echo "Logging into $FTP_HOST to check for new files"
    cd $IN_DIR
ftp -p -n -v $FTP_HOST <<EOT
user $FTP_USER $FTP_PASS
cd $FTP_PATH
get $AFILE
get $BFILE
bye
EOT
cd $WORK_DIR
}

ImportBibs () {
    echo "Inside ImportBibs: $(pwd) \$1 is $1 and \$2 is $2"
    echo "file listing is $(ls)"
    BATCHBASE="$1"
    BIBFILE="$2"
    BATCH="$(echo $BATCHBASE | tr [:upper:] [:lower:] | sed 's/\./_/g')_$(basename -s .MRC $BIBFILE | tr [:upper:] [:lower:] | sed 's/\./_/g')"
    echo "BATCH is $BATCH"
    for action in stage_bibs load_bibs link_auth_bib; do
        if [ "$action" == "stage_bibs" ]; then
            echo "\$action is $action"
            FILES=" -- $BIBFILE"
        fi
        $SCRIPT --schema $BIB_SCHEMA --batch $BATCH --db $DB_NAME --dbhost $DB_HOST --dbuser $DB_USER --action $action $FILES
    done
}

ImportAuths () {
    BATCHBASE="$1"
    AUTHFILE="$2"
    BATCH="$(echo $BATCHBASE | tr [:upper:] [:lower:] | sed 's/\./_/g')_$(basename -s .MRC $AUTHFILE | tr [:upper:] [:lower:] | sed 's/\./_/g')"
    for action in stage_auths match_auths load_new_auths overlay_auths_stage1 overlay_auths_stage2 overlay_auths_stage3 link_auth_auth report; do
        if [ "$action" == "stage_auths" ]; then
            FILES=" -- $AUTHFILE"
        fi
        $SCRIPT --schema $AUTH_SCHEMA --batch $BATCH --db $DB_NAME --dbhost $DB_HOST --dbuser $DB_USER --action $action $FILES
    done
}

FTPFiles
cd $WORK_DIR
for zipfile in In/*.zip; do
    echo $zipfile
    cd $IN_DIR && pwd
    BASENAME=$(basename -s .zip $zipfile)
    echo "\$BASENAME = $BASENAME"
    unzip $BASENAME.zip -d $BASENAME
    cd $BASENAME && pwd
    for bibfile in $(find . -name "BIB.MRC" -print); do
        echo "Processing $bibfile"
        ImportBibs $BASENAME $bibfile
    done
# currently not importing auth files - csharp 2026/09/29
#    for authfile in $(find . -name "*.MRC" ! -name "BIB.MRC" -print); do
#        echo "Processing $authfile"
#        ImportAuths $BASENAME $authfile
#    done
    cd $WORK_DIR && pwd
    rm $IN_DIR/$BASENAME
    mv $IN_DIR/$zipfile $WORK_DIR/$DONE_DIR
done
