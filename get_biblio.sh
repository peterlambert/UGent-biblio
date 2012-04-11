#!/bin/bash

h="#
# ##############################################################################
#
# Written by Peter Lambert (peter.lambert@ugent.be, www.peterlambert.be)
# (c) Ghent University, 2012
#
# What does this script do?
# ========================= 
# 	- It downloads all bibtex records of an UGent employee 
#	  as a set of .bib files from biblio.ugent.be
#	- It adds the JCR impact factors for every A1 publication 
#	  in the A1 bibtex file (as a note)
#	- It generates a LaTeX enumeration environment per publication 
#	  classification and inserts them in a LaTeX template
#	- It generates a PDF file with all publications
#
# What does this script rely on?
# ================================
#	- sed, grep, cat, curl, bibtex, pdflatex (and an Internet connection)
#	- a LaTeX template file (e.g., report) with placeholders 
#	  for the publication lists per classification
#
# Command line arguments:
# =======================
#	1: ugentID 		(e.g., 801001642993)
#	2: sort order 		(i.e., desc or asc)
#	3: template file 	(e.g., bibliografie_template.tex) 
#	   (placeholders:  	\"{___A1___}\" without double quotes)
# 	4: output file 		(e.g., bibliografie.tex)
# 
# ##############################################################################
#
"

#
# Some init stuff
#

NUMPARAMS=4

# Check if we have the correct number of command line parameters
if [[ "$#" -eq 1 && "$1" == "-h" ]]
then
  echo "$h"
  exit 1
else
  if [ "$#" -ne "$NUMPARAMS" ]
  then
    echo "Usage: $0 [UGent ID] [desc|asc] [template file] [output file]"
    echo "Try \`$0 -h\` for more information."
    echo ""
    exit 1
  fi
fi 

# Setting some variables
# datum=$(date +"%d-%m-%Y")
begin="\\begin{enumerate}"
end="\\end{enumerate}"

# Assign command line arguments to variables
# Watch out: there is no sanity check on the input (I trust myself, but do you?)
ugentid="$1"	# "801001642993"
sort="$2"	# "asc"
template="$3"	# "bibliografie_template.tex"
output="$4"	# "bibliografie.tex"


#
# Download .bib file for every publication category (using the bibtex export functionality)
#

for type in A1 A2 A3 A4 B1 B2 B3 C1 C2 C3 P1 D1
do
  curl "https://biblio.ugent.be/publication/export?q._all.text={$ugentid}&q.classification.text={$type}&limit=1000&sort=year.{$sort}&format=bibtex" > $type.bib
done


#
# For every category: fetch the publication IDs en transform them in a LaTeX enumeration environment string
#

# temporary file
cp $template vorige.tex

for type in A1 A2 A3 A4 B1 B2 B3 C1 C2 C3 P1 D1
  do

  # Create enumeration for LaTeX (or just "nihil." in case of an empty .bib file)
  if [ -s $type.bib ] 
  then
    echo "$begin" > tmplist
    cat $type.bib | grep -e "@[a-z]\{1,\}{.*," | sed -e "s/^@[^ {]*{\(.*\),/\\\item\ \\\bibentry{\1}/g" >> tmplist
    echo "$end" >> tmplist
  else
    echo "nihil." > tmplist
  fi

  #
  # Here is some fishy (or at least kinky) stuff for automatic impact factor insertion (AIFI)
  #

  # If we are dealing with A1 publications...
  if [ "$type" = "A1" ]
  then

    # First, spit out the A1 IDs
    cp tmplist tmplistA1
    cat tmplistA1 | sed -e "s/[^ 0-9]//g" | sed -e "s/\ //g" | grep -v '^$' > listA1
    rm -f tmplistA1

    # We loop over all IDs in listA1
    while read id
    do
    
      # Silently download the JSON export of this particular publication ...
      curl "https://biblio.ugent.be/publication/{$id}.json" > jsondoc

      # ... and search for the Impact Factor (or the previous one)
      if1=$(cat jsondoc | grep -Po '"impact_factor":[\.0-9]+'|sed -e "s/^[^ :]*://g")

      if [ -z $if1 ]
      then
        if2=$(cat jsondoc | grep -Po '"prev_impact_factor":[\.0-9]+'|sed -e "s/^[^ :]*://g")  
        if [ -z $if2 ]
        then
          if="n/a"
        else
          if=$if2
        fi  
      else
        if=$if1
      fi

      # Craft an extra line for the bibtex record with the IF as a note
      echo -e "@article{${id},\n\n\tnote\t=\t{(SCI: ${if})},\n" > insertline

      # Insert the crafted line at the right place in the original .bib file
sed "/{${id},/ {r insertline
d;};" A1.bib > A1new.bib

      mv A1new.bib A1.bib

    done < listA1

    # We now have an enhanced version of the A1 bibtex file 
    # removing some temporary files
    rm -f jsondoc insertline listA1
  
  fi # end of A1-specific stuff

  # replace the placeholders with the enumeration string
sed "/___${type}___/ {r tmplist
d;};" vorige.tex > volgende.tex

  mv volgende.tex vorige.tex
  sed -i -e 's///g' vorige.tex
  rm -f tmplist
  rm -f "vorige.tex-e"

done

# The latest "vorige.tex" file is the final output .tex file
mv vorige.tex $output


#
# Generate PDF using pdflatex and bibtex
#

outputshort=$(echo $output | sed -e 's/\.[^ \.]*$//g')

pdflatex $output
bibtex $outputshort
pdflatex $output
pdflatex $output


#
# Some cleaning up
#
rm -f $outputshort.bbl $outputshort.blg $outputshort.log $outputshort.aux


exit 0
# end

