#!/bin/bash
echo "
 _____     _           ____
| ____|___| |__   ___ |  _ \__      ___ __
|  _| / __| '_ \ / _ \| |_) \ \ /\ / / '_ \\
| |__| (__| | | | (_) |  __/ \ V  V /| | | |
|_____\___|_| |_|\___/|_|     \_/\_/ |_| |_|v1.1

"

help(){
  echo "
Usage: ./EchoPwn.sh [options] -d domain.com
Options:
    -h            Display this help message.
    -k            Run Knockpy on the domain.

  Target:
    -d            Specify the domain to scan.

Example:
    ./EchoPwn.sh -d hackerone.com
"
}

POSITIONAL=()

if [[ "$*" != *"-d"* ]]
then
	help
  exit
fi

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -h|--help)
    help
    exit
    ;;
    -d|--domain)
    d="$2"
    shift
    shift
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters
echo "Clear old results"
rm -r EchoPwn/$d
echo "Starting SubEnum $d"

echo "Creating directory"
#set -e - gap error terminate
if [ ! -d $PWD/EchoPwn ]; then
	mkdir EchoPwn
fi
if [ ! -d $PWD/EchoPwn/$d ]; then
	mkdir EchoPwn/$d
fi
source tokens.txt


if [[ "$*" = *"-k"* ]]
then
	echo "Starting KnockPy"
	mkdir EchoPwn/$d/knock
	cd EchoPwn/$d/knock; python ../../../knock/knockpy/knockpy.py "$d" -j; cd ../../..
fi

echo "Starting Sublist3r..."
python3 Sublist3r/sublist3r.py -d "$d" -o EchoPwn/$d/fromsublister.txt

echo "Amass turn..."
amass enum --passive -d $d -o EchoPwn/$d/fromamass.txt

echo "Starting subfinder..."
subfinder -d $d -o EchoPwn/$d/fromsubfinder.txt -v --exclude-sources dnsdumpster

echo "Starting assetfinder..."
assetfinder --subs-only $d > EchoPwn/$d/fromassetfinder.txt

echo "Starting aquatone-discover"
aquatone-discover -d $d --disable-collectors dictionary -t 300
rm -rf amass_output
cat ~/aquatone/$d/hosts.txt | cut -f 1 -d ',' | sort -u >> EchoPwn/$d/fromaquadiscover.txt
rm -rf ~/aquatone/$d/

echo "Starting github-subdomains..."
python3 github-subdomains.py -t $github_token_value -d $d | sort -u >> EchoPwn/$d/fromgithub.txt

echo "Starting findomain"

./findomain -t $d -r -u EchoPwn/$d/fromfindomain.txt

cat EchoPwn/$d/*.txt | grep $d | grep -v '*' | sort -u  >> EchoPwn/$d/alltogether.txt

echo "Deleting other(older) results"
rm -rf EchoPwn/$d/from*

echo "Resolving - Part 1"
./massdns/bin/massdns -r massdns/lists/resolvers.txt -s 1000 -q -t A -o S -w /tmp/massresolved1.txt EchoPwn/$d/alltogether.txt
awk -F ". " "{print \$1}" /tmp/massresolved1.txt | sort -u >> EchoPwn/$d/resolved1.txt
rm /tmp/massresolved1.txt
rm EchoPwn/$d/alltogether.txt

echo "Removing wildcards"
python3 wildcrem.py EchoPwn/$d/resolved1.txt >> EchoPwn/$d/resolved1-nowilds.txt
rm EchoPwn/$d/resolved1.txt

echo "Starting AltDNS..."
altdns -i EchoPwn/$d/resolved1-nowilds.txt -o EchoPwn/$d/fromaltdns.txt -t 300

echo "Resolving - Part 2 - Altdns results"
./massdns/bin/massdns -r massdns/lists/resolvers.txt -s 1000 -q -o S -w /tmp/massresolved1.txt EchoPwn/$d/fromaltdns.txt
awk -F ". " "{print \$1}" /tmp/massresolved1.txt | sort -u >> EchoPwn/$d/altdns-resolved.txt
rm /tmp/massresolved1.txt
rm EchoPwn/$d/fromaltdns.txt

echo "Removing wildcards - Part 2"
python3 wildcrem.py EchoPwn/$d/altdns-resolved.txt >> EchoPwn/$d/altdns-resolved-nowilds.txt
rm EchoPwn/$d/altdns-resolved.txt

cat EchoPwn/$d/*.txt | sort -u > EchoPwn/$d/$d.txt
rm EchoPwn/$d/altdns-resolved-nowilds.txt
rm EchoPwn/$d/resolved1-nowilds.txt


echo "Appending http/s to hosts"
cat EchoPwn/$d/$d.txt | sort -u | ~/go/bin/httprobe | tee -a EchoPwn/$d/httprobe.txt

echo "Taking screenshots..."
cat EchoPwn/$d/httprobe.txt | aquatone -ports xlarge -out EchoPwn/$d/aquascreenshots

echo "Total hosts found: $(wc -l EchoPwn/$d/$d.txt)"


echo "Starting Nmap"
if [ ! -d $PWD/EchoPwn/$d/nmap ]; then
	mkdir EchoPwn/$d/nmap
fi
for i in $(cat EchoPwn/$d/$d.txt); do nmap -sC -sV $i -o EchoPwn/$d/nmap/$i.txt; done

echo "Starting DirSearch"
if [ ! -d $PWD/EchoPwn/$d/dirsearch ]; then
	mkdir EchoPwn/$d/dirsearch
fi
for i in $(cat EchoPwn/$d/$d.txt); do python3 dirsearch/dirsearch.py -e php,asp,aspx,jsp,html,zip,jar -w dirsearch/db/dicc.txt -t 5 -u $i --plain-text-report="EchoPwn/$d/dirsearch/$i.txt"; done

echo "Starting Photon Crawler"
if [ ! -d $PWD/EchoPwn/$d/photon ]; then
  mkdir EchoPwn/$d/photon
fi
for i in $(cat EchoPwn/$d/aquascreenshots/aquatone_urls.txt); do python3 Photon/photon.py -u $i -o EchoPwn/$d/photon/$(cut -d "/" -f 3 <<<"$i") -l 2 -t 5; done

echo "Scan vulnerabilities"
./vuln-scan.sh -d $d
#echo "Notifying you on Pushover"
python3 notify.py

echo "Finished successfully."

