find -type f -a ! -path '*CVS*' -a ! -path './debian/*' -a ! -path './blib/*' -a ! -name pm_to_blib -a ! -name build-stamp -a ! -name manifest.sh -a ! -name '.*'|sed -e 's/^\.\///' > MANIFEST
