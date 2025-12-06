import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from bs4 import BeautifulSoup
import json
import datetime
import re
import sys
import time
import hashlib
from concurrent.futures import ThreadPoolExecutor, as_completed
from github import Github, Auth
from flask import Flask 
from threading import Thread 
import os 

# ==========================================
# ⚙️ إعدادات البوت (يتم جلبها من Environment Variables)
# ==========================================
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
REPO_NAME = os.getenv("REPO_NAME")
FILE_PATH_IN_REPO = os.getenv("FILE_PATH_IN_REPO", "today.json") 
TELEGRAM_TOKEN = os.getenv("TELEGRAM_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")

CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", 60)) # جعلت الافتراضي 60 ثانية للأفضلية

# ==========================================
# إعداد سيرفر وهمي (Flask) ليعمل على Render
# ==========================================
app = Flask('')

@app.route('/')
def home():
    return "I am alive! The Bot is running..."

def run():
    app.run(host='0.0.0.0', port=8080)

def keep_alive():
    t = Thread(target=run)
    t.start()

# ==========================================
# 1. إعدادات الاتصال 
# ==========================================
BASE_URL = "https://www.ysscores.com"
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Referer': 'https://www.google.dz/', # تحسين بسيط: المصدر جوجل الجزائر
    'Accept-Language': 'ar-DZ,ar;q=0.9,fr-DZ;q=0.8,fr;q=0.7,en;q=0.5', # لغة الجزائر
}

session = requests.Session()
retry_strategy = Retry(
    total=3,
    backoff_factor=1,
    status_forcelist=[429, 500, 502, 503, 504],
)
adapter = HTTPAdapter(pool_connections=20, pool_maxsize=20, max_retries=retry_strategy)
session.mount("https://", adapter)
session.mount("http://", adapter)
session.headers.update(HEADERS)

def clean_text(text):
    if text:
        return text.strip().replace('\n', ' ').replace('\r', '').replace('  ', ' ')
    return None

def get_match_deep_details(match_url):
    if not match_url: return None
    full_url = match_url if match_url.startswith('http') else f"{BASE_URL}{match_url}"
    
    try:
        response = session.get(full_url, timeout=10)
        soup = BeautifulSoup(response.text, 'html.parser')
        
        match_details = {
            "url": full_url, "info": {}, "teams": {}, "channels": []
        }

        # الفرق
        team_divs = soup.find_all('div', class_=re.compile(r'(team|club)'))
        main_teams = [t for t in team_divs if t.find('img')][:2]
        
        if len(main_teams) >= 2:
            t1_name = main_teams[0].get_text(strip=True)
            t1_img = main_teams[0].find('img')['src']
            t2_name = main_teams[1].get_text(strip=True)
            t2_img = main_teams[1].find('img')['src']
            match_details["teams"]["home"] = {"name": t1_name, "logo": t1_img}
            match_details["teams"]["away"] = {"name": t2_name, "logo": t2_img}
        else:
            title_tag = soup.find('title')
            match_details["teams"]["full_title"] = title_tag.text.strip() if title_tag else "مباراة غير معروفة"

        # المعلومات
        target_keys = {"البطولة": "championship", "الجولة": "round", "ملعب المباراة": "stadium", 
                       "وقت المباراة": "time", "تاريخ المباراة": "date"}
        info_block = soup.find('div', class_='match-info') or soup
        for label in info_block.find_all(string=re.compile(r'البطولة|الجولة|ملعب|وقت|تاريخ')):
            clean_lbl = clean_text(label)
            for key_ar, key_en in target_keys.items():
                if key_ar in clean_lbl:
                    parent = label.find_parent()
                    val_elem = parent.find_next_sibling() or parent.find('span', class_='value')
                    val = clean_text(val_elem.text) if val_elem else clean_text(parent.get_text().replace(key_ar, ''))
                    match_details["info"][key_en] = val

        # ========================================================
        # 🔥 تصحيح سحب النتيجة والحالة (بناءً على HTML الجديد) 🔥
        # ========================================================
        
        # 1. سحب النتيجة من <div class="main-result"> وداخلها <b>
        current_score = "- : -"
        main_result_div = soup.find('div', class_='main-result')
        
        if main_result_div:
            # البحث عن وسوم العريض <b> التي تحتوي الأهداف
            score_tags = main_result_div.find_all('b')
            if len(score_tags) >= 2:
                # الهدف الأول (يمين) - الهدف الثاني (يسار)
                s1 = clean_text(score_tags[0].text)
                s2 = clean_text(score_tags[1].text)
                
                # التأكد أنهم أرقام لتجنب سحب نصوص خطأ
                if s1.isdigit() and s2.isdigit():
                    current_score = f"{s1} - {s2}"
                else:
                    # محاولة تنظيف إضافية
                    current_score = f"{s1} - {s2}"

        match_details["info"]["current_score"] = current_score

        # 2. سحب الحالة من <span class="result-status-text">
        match_status = "لم تبدأ"
        status_span = soup.find('span', class_='result-status-text')
        
        if status_span:
            st_text = clean_text(status_span.text)
            if st_text:
                match_status = st_text
        else:
            # محاولة احتياطية من الوقت
            status_div_backup = soup.find('div', class_=re.compile(r'(match-status|status)'))
            if status_div_backup:
                 match_status = clean_text(status_div_backup.text)

        match_details["info"]["match_status"] = match_status
        # ========================================================

        # القنوات
        section_header = soup.find(string=re.compile(r'القنوات الناقلة والمعلقين'))
        if section_header:
            block_container = section_header.find_parent('div', class_='match-block-item')
            if block_container:
                channel_rows = block_container.find_all('div', class_='match-info-item sub')
                for row in channel_rows:
                    title_div = row.find('div', class_='title')
                    content_div = row.find('div', class_='content')
                    match_details["channels"].append({
                        "channel": clean_text(title_div.text) if title_div else "غير محدد",
                        "commentator": clean_text(content_div.text) if content_div else "غير محدد"
                    })

        if not match_details["channels"]:
            comm_single = soup.find(string=re.compile(r'^المعلق$'))
            ch_single = soup.find(string=re.compile(r'^القناة$'))
            if comm_single and ch_single:
                c_val = ch_single.find_parent().find_next_sibling()
                m_val = comm_single.find_parent().find_next_sibling()
                if c_val and m_val:
                    match_details["channels"].append({
                        "channel": clean_text(c_val.text),
                        "commentator": clean_text(m_val.text)
                    })

        return match_details

    except Exception:
        return None

def main_scraper():
    url = f"{BASE_URL}/ar/index"
    try:
        response = session.get(url, timeout=15)
        soup = BeautifulSoup(response.text, 'html.parser')
    except Exception as e:
        print(f"Error: {e}")
        return None

    links = set()
    for a in soup.find_all('a', href=re.compile(r'/match/\d+')):
        links.add(a['href'])
    
    links_list = list(links)
    total = len(links_list)
    print(f"[*] Found {total} matches.")

    final_data = []
    with ThreadPoolExecutor(max_workers=20) as executor:
        future_to_url = {executor.submit(get_match_deep_details, u): u for u in links_list}
        for future in as_completed(future_to_url):
            data = future.result()
            if data: final_data.append(data)

    return sorted(final_data, key=lambda x: x['info'].get('championship', ''))

def update_github_file(content_json):
    try:
        auth = Auth.Token(GITHUB_TOKEN)
        g = Github(auth=auth)
        repo = g.get_repo(REPO_NAME)
        content_str = json.dumps(content_json, indent=2, ensure_ascii=False)
        content_bytes = content_str.encode("utf-8")
        try:
            contents = repo.get_contents(FILE_PATH_IN_REPO)
            repo.update_file(contents.path, f"Update matches: {datetime.datetime.now().strftime('%H:%M')}", content_bytes, contents.sha)
            print("✅ GitHub Updated.")
        except:
            repo.create_file(FILE_PATH_IN_REPO, "Initial commit", content_bytes)
            print("✅ GitHub Created.")
        return True
    except Exception as e:
        print(f"❌ GitHub Error: {e}")
        return False

def send_telegram_alert(message):
    if TELEGRAM_TOKEN and TELEGRAM_CHAT_ID:
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        data = {"chat_id": TELEGRAM_CHAT_ID, "text": message}
        try: session.post(url, data=data, timeout=5)
        except: pass

def monitor_matches():
    last_hash = ""
    print(f"🚀 Bot Started monitoring {BASE_URL}...")
    send_telegram_alert("🚀 Bot Started on Render.")

    while True:
        try:
            current_data = main_scraper()
            if current_data:
                current_json_str = json.dumps(current_data, sort_keys=True)
                current_hash = hashlib.md5(current_json_str.encode('utf-8')).hexdigest()
                if current_hash != last_hash:
                    print("🔄 Change detected! Updating...")
                    if update_github_file(current_data):
                        last_hash = current_hash
                else:
                    print("💤 No changes.")
            
            time.sleep(CHECK_INTERVAL)

        except Exception as e:
            print(f"⚠️ Loop Error: {e}")
            time.sleep(60)

if __name__ == "__main__":
    # تشغيل السيرفر الوهمي في خيط منفصل
    keep_alive()
    
    # التحقق من وجود التوكين قبل البدء
    if not GITHUB_TOKEN:
        print("❌ الخطأ: لم يتم العثور على GITHUB_TOKEN في متغيرات البيئة!")
        print("تأكد من إضافته في إعدادات Render (Environment Variables).")
    elif "YOUR_GITHUB_TOKEN" in GITHUB_TOKEN:
         print("❌ الخطأ: يبدو أنك تستخدم النص الافتراضي للتوكين، يرجى وضع التوكين الصحيح.")
    else:
        # البدء بالمراقبة
        monitor_matches()
