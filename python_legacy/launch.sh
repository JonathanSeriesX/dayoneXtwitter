xcode-select -p > /dev/null 2>&1 || xcode-select --install
[ -d venv ] || python3 -m venv venv
source venv/bin/activate
pip3 install --upgrade pip --quiet
pip3 install -r requirements.txt --quiet
python3 main.py