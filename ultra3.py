import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry
from bs4 import BeautifulSoup
import json
import datetime
from datetime import timedelta
import re
import sys
import time
import hashlib
from concurrent.futures import ThreadPoolExecutor, as_completed
# ✅ استيراد مكتبات Firebase
import firebase_admin
from firebase_admin import credentials, firestore
from flask import Flask 
from threading import Thread 
import os 

# ==========================================
# ⚙️ إعدادات البوت وقاعدة البيانات
# ==========================================
# ✅ جلب مفاتيح Firebase من متغيرات البيئة
FIREBASE_CREDENTIALS_JSON = os.getenv("FIREBASE_CREDENTIALS")
TELEGRAM_TOKEN = os.getenv("TELEGRAM_TOKEN")
TELEGRAM_CHAT_ID = os.getenv("TELEGRAM_CHAT_ID")

CHECK_INTERVAL = int(os.getenv("CHECK_INTERVAL", 60))

# ✅ تهيئة الاتصال بـ Cloud Firestore
db = None
if FIREBASE_CREDENTIALS_JSON:
    try:
        cred_dict = json.loads(FIREBASE_CREDENTIALS_JSON)
        cred = credentials.Certificate(cred_dict)
        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred)
        db = firestore.client()
        print("✅ Cloud Firestore Initialized Successfully.")
    except Exception as e:
        print(f"❌ Firestore Init Error: {e}")
else:
    print("⚠️ Warning: FIREBASE_CREDENTIALS is missing.")

# ==========================================
# إعداد سيرفر وهمي (Flask)
# ==========================================
app = Flask('')

@app.route('/')
def home():
    return "I am alive! The Bot is running with Firestore..."

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
    'Referer': 'https://www.google.dz/',
    'Accept-Language': 'ar-DZ,ar;q=0.9,fr-DZ;q=0.8,fr;q=0.7,en;q=0.5',
}

session = requests.Session()
retry_strategy = Retry(
    total=3, backoff_factor=1, status_forcelist=[429, 500, 502, 503, 504],
)
adapter = HTTPAdapter(pool_connections=20, pool_maxsize=20, max_retries=retry_strategy)
session.mount("https://", adapter)
session.mount("http://", adapter)
session.headers.update(HEADERS)

# ==========================================
# 🛠️ الدوال (لم يتم تغيير أي شيء في المنطق)
# ==========================================
def convert_to_algeria_time(time_str):
    if not time_str or ":" not in time_str:
        return time_str
    try:
        is_pm = "م" in time_str or "مساء" in time_str
        clean_time = re.sub(r'[^0-9:]', '', time_str)
        match_time = datetime.datetime.strptime(clean_time, "%H:%M")

        if is_pm and match_time.hour != 12:
            match_time = match_time.replace(hour=match_time.hour + 12)
        elif not is_pm and match_time.hour == 12:
            match_time = match_time.replace(hour=0)

        new_time = match_time + timedelta(hours=6) 
        return new_time.strftime("%H:%M")
    except:
        return time_str

def clean_text(text):
    if text:
        return text.strip().replace('\n', ' ').replace('\r', '').replace('  ', ' ')
    return None

# ==========================================
# ✅ الدالة المحدثة (للعمل مع التصميم الجديد)
# ==========================================
def get_match_deep_details(match_url):
    if not match_url: return None
    # تصحيح الرابط إذا لم يكن كاملاً
    full_url = match_url if match_url.startswith('http') else f"{BASE_URL}{match_url}"
    
    try:
        response = session.get(full_url, timeout=10)
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # استخراج ID المباراة
        match_id = "0"
        id_search = re.search(r'/match/(\d+)', full_url)
        if id_search:
            match_id = id_search.group(1)

        match_details = {
            "id": match_id,
            "url": full_url, 
            "info": {}, 
            "teams": {}, 
            "channels": []
        }

        # 1. استخراج الفرق (التصميم الجديد)
        # نبحث عن الحاوية الرئيسية للفرق
        profile_details = soup.find('div', class_='match-profile-details')
        if profile_details:
            team_items = profile_details.find_all('div', class_='team-item')
            if len(team_items) >= 2:
                # الفريق الأول (عادة اليمين/صاحب الأرض)
                t1_h3 = team_items[0].find('h3')
                t1_img_tag = team_items[0].find('img')
                
                t1_name = t1_h3.get_text(strip=True) if t1_h3 else "فريق 1"
                t1_img = t1_img_tag['src'] if t1_img_tag else ""
                
                # الفريق الثاني (اليسار/الضيف)
                t2_h3 = team_items[1].find('h3')
                t2_img_tag = team_items[1].find('img')

                t2_name = t2_h3.get_text(strip=True) if t2_h3 else "فريق 2"
                t2_img = t2_img_tag['src'] if t2_img_tag else ""

                match_details["teams"]["home"] = {"name": t1_name, "logo": t1_img}
                match_details["teams"]["away"] = {"name": t2_name, "logo": t2_img}
        
        # إذا فشل في إيجاد الفرق بالطريقة الجديدة، نستخدم العنوان كاحتياط
        if not match_details["teams"]:
            title_tag = soup.find('title')
            match_details["teams"]["full_title"] = title_tag.text.strip() if title_tag else "مباراة غير معروفة"

        # 2. استخراج المعلومات (البطولة، الوقت، القنوات، المعلق)
        # الموقع الجديد يضع كل معلومة داخل div class="match-info-item"
        info_items = soup.find_all('div', class_='match-info-item')
        
        # قاموس لترجمة العناوين العربية إلى مفاتيح JSON
        key_map = {
            "البطولة": "championship",
            "الجولة": "round",
            "ملعب المباراة": "stadium",
            "وقت المباراة": "time",
            "تاريخ المباراة": "date",
            "القناة": "channel",
            "المعلق": "commentator"
        }

        temp_channels = {"channel": "غير محدد", "commentator": "غير محدد"}
        channel_found = False

        for item in info_items:
            title_div = item.find('div', class_='title')
            content_div = item.find('div', class_='content')
            
            if title_div and content_div:
                raw_title = title_div.get_text(strip=True)
                raw_value = content_div.get_text(strip=True)
                
                # البحث عن المفتاح المناسب
                for ar_key, en_key in key_map.items():
                    if ar_key in raw_title:
                        # معالجة خاصة للوقت
                        if en_key == "time":
                            match_details["info"][en_key] = convert_to_algeria_time(raw_value)
                        # معالجة القنوات والمعلقين
                        elif en_key == "channel":
                            temp_channels["channel"] = clean_text(raw_value)
                            channel_found = True
                        elif en_key == "commentator":
                            temp_channels["commentator"] = clean_text(raw_value)
                            channel_found = True
                        else:
                            match_details["info"][en_key] = clean_text(raw_value)

        # إضافة القنوات إذا وجدت
        if channel_found:
            match_details["channels"].append(temp_channels)

        # 3. حالة المباراة والنتيجة (من التصميم الجديد)
        current_score = "- : -"
        match_status = "لم تبدأ"
        
        # البحث في div match-details الذي يقع بين الفريقين
        details_box = soup.find('div', class_='match-details')
        if details_box:
            # التحقق من الحالة (مثل "تبدأ قريباً" أو المؤقت)
            status_span = details_box.find('span', class_='timer')
            if status_span:
                status_text = status_span.get_text(strip=True)
                # إذا كان النص يحتوي على أرقام فقط (عداد تنازلي) نعتبرها لم تبدأ
                if not re.search(r'\d{2}\s*:\s*\d{2}', status_text): 
                     match_status = status_text
            
            # محاولة العثور على النتيجة إذا كانت المباراة جارية أو منتهية
            # عادة تكون داخل هذا الصندوق كنص مباشر أو عناصر b
            box_text = details_box.get_text(strip=True)
            score_match = re.search(r'(\d+)\s*[:\-]\s*(\d+)', box_text)
            
            if score_match:
                current_score = f"{score_match.group(1)} - {score_match.group(2)}"
                # إذا وجدنا نتيجة، نعتبر المباراة جارية إلا إذا وجدنا كلمة انتهت
                if "انتهت" not in box_text and "Full Time" not in box_text:
                    match_status = "جارية"
            
            # فحص إضافي لحالة النهاية من كامل الصفحة
            if soup.find(string=re.compile(r'(إنتهت المباراة|Full Time)')):
                match_status = "إنتهت المباراة"

        match_details["info"]["current_score"] = current_score
        match_details["info"]["match_status"] = match_status

        return match_details

    except Exception as e:
        print(f"Error extracting details for {full_url}: {e}")
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

# ==========================================
# 🆕 دالة الحفظ في Cloud Firestore
# ==========================================
def update_firestore_db(matches_list):
    if not db:
        return False
        
    try:
        # استخدام Batch لضمان السرعة في التحديث
        batch = db.batch()
        collection_ref = db.collection('matches')

        count = 0
        for match in matches_list:
            # ✅ استخدام ID المباراة كـ Document ID لتجنب التكرار وضمان التحديث
            doc_id = str(match['id']) 
            doc_ref = collection_ref.document(doc_id)
            
            # حفظ بيانات المباراة
            batch.set(doc_ref, match, merge=True)
            count += 1
            
            # Firestore Limit: 500 ops per batch
            if count >= 450:
                batch.commit()
                batch = db.batch()
                count = 0
        
        if count > 0:
            batch.commit()
            
        print(f"✅ Firestore Updated: {len(matches_list)} today.")
        return True
    except Exception as e:
        print(f"❌ Firestore Error: {e}")
        return False

def send_telegram_alert(message):
    if TELEGRAM_TOKEN and TELEGRAM_CHAT_ID:
        url = f"https://api.telegram.org/bot{TELEGRAM_TOKEN}/sendMessage"
        data = {"chat_id": TELEGRAM_CHAT_ID, "text": message}
        try: session.post(url, data=data, timeout=5)
        except: pass

def monitor_matches():
    last_hash = ""
    last_update_day = datetime.date.min
     
    print(f"🚀 Bot Started monitoring {BASE_URL}...")
    send_telegram_alert("🚀 Bot Started on Render (Firestore).")

    while True:
        try:
            current_data = main_scraper()
            current_date = datetime.date.today()
             
            if current_data:
                current_json_str = json.dumps(current_data, sort_keys=True)
                current_hash = hashlib.md5(current_json_str.encode('utf-8')).hexdigest()
                
                force_update = (current_date > last_update_day)
                
                if current_hash != last_hash or force_update:
                    if force_update:
                         print("🔄 NEW DAY: Forcing update.")
                    else:
                         print("🔄 Change detected! Updating...")

                    # ✅ الحفظ في Cloud Firestore بدلاً من GitHub
                    if update_firestore_db(current_data):
                        last_hash = current_hash
                        last_update_day = current_date 
                else:
                    print("💤 No changes.")
             
            time.sleep(CHECK_INTERVAL)

        except Exception as e:
            print(f"⚠️ Loop Error: {e}")
            time.sleep(60)

if __name__ == "__main__":
    keep_alive()
    monitor_matches()
