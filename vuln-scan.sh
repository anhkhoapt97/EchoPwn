#!/bin/bash
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
echo "Starting Arjun..."
arjun -i EchoPwn/$d/httprobe.txt -oT EchoPwn/$d/arjun_out-temp.txt -w Arjun/arjun/db/params.txt 

cat EchoPwn/$d/arjun_out-temp.txt | sed 's/[[:digit:]][[:digit:]][[:digit:]][[:digit:]]/\&/g' > EchoPwn/$d/arjun_out.txt

echo "Checking for Subdomain Takeover"
python3 subdomain-takeover/takeover.py -d $d -f EchoPwn/$d/$d.txt -t 5 | tee EchoPwn/$d/subdomain_takeover.txt

echo "Scan CVEs with nuclei"
nuclei -l EchoPwn/$d/$d.txt -t cves/ > EchoPwn/$d/nuclei-cve-results.txt

echo "Scan XSS vulnerabilities"
cat EchoPwn/$d/arjun_out.txt | Zin -p '"><script>alert("xsstest")</script>' -g xsstest | grep -oP "(http|https)://[^']+" > EchoPwn/$d/Raw-result-xss.txt

if [ -s $PWD/EchoPwn/$d/Raw-result-xss.txt ]; then 
	for i in $(cat EchoPwn/$d/Raw-result-xss.txt); do curl $i -IL | grep xsstest >>/dev/null && echo $i >> EchoPwn/$d/Scan-XSS-Result.txt; done
fi
rm EchoPwn/$d/Raw-result-xss.txt


