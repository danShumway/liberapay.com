#!/bin/sh


# Fail on error
set -e


# Be somewhere predictable
cd "`dirname $0`"


# --help
if [ "$1" = "" ]; then
    echo
    echo "Usage: $0 <version>"
    echo
    echo "  This is a release script for Gratipay. We do a git dance, pushing to Heroku."
    echo
    exit
fi


# Helpers

yesno () {
    proceed=""
    while [ "$proceed" != "y" ]; do
        read -p"$1 (y/n) " proceed
        [ "$proceed" = "n" ] && return 1
    done
    return 0
}

require () {
    if [ ! `which $1` ]; then
        echo "The '$1' command was not found."
        exit 1
    fi
}


# Check that we have the required tools
require heroku
require git


# Make sure we have the latest master

if [ "`git rev-parse --abbrev-ref HEAD`" != "master" ]; then
    echo "Not on master, checkout master first."
    exit
fi

git pull

if [ "`git tag | grep $1`" ]; then
    echo "Version $1 is already git tagged."
    exit
fi


# Check that the environment contains all required variables
heroku config -sa gratipay | ./env/bin/honcho run -e /dev/stdin \
    ./env/bin/python gratipay/wireup.py


# Check for a branch.sql
if [ -e branch.sql ]; then
    # Merge branch.sql into schema.sql
    git rm --cached branch.sql
    echo | cat branch.sql >>schema.sql
    echo "branch.sql has been appended to schema.sql"
    read -p "If you have manual modifications to make to schema.sql do them now, then press Enter to continue... " enter
    git add schema.sql
    git commit -m "merge branch.sql into schema.sql"

    # Deployment options
    if yesno "Should branch.sql be applied before deploying to Heroku instead of after?"; then
        run_sql="before"
        if yesno "Should the maintenance mode be turned on during deployment?"; then
            maintenance="yes"
        fi
    else
        run_sql="after"
    fi
fi


# Ask confirmation and bump the version
yesno "Tag and deploy version $1?" || exit
git tag $1


# Deploy to Heroku
[ "$maintenance" = "yes" ] && heroku maintenance:on -a gratipay
[ "$run_sql" = "before" ] && heroku pg:psql -a gratipay <branch.sql
git push heroku master
[ "$maintenance" = "yes" ] && heroku maintenance:off -a gratipay
[ "$run_sql" = "after" ] && heroku pg:psql -a gratipay <branch.sql
rm -f branch.sql


# Push to GitHub
git push
git push --tags
