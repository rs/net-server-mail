find README Changes Makefile.PL eg/ lib/ t/ -type f -a ! -path '*CVS*'|sed -e 's/^\.\///' > MANIFEST
