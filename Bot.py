import threading
import os
from flask import Flask
import requests
import base64
from itertools import cycle
import json
import logging
import time
from telegram import Update

# (v20) هذا هو السطر الصحيح للإصدار الحديث
from telegram.ext import Application, CommandHandler, CallbackContext 

# --- 1. إعدادات التليجرام وجيت هاب (تُقرأ من Render) ---

BOT_TOKEN = os.environ.get("BOT_TOKEN")
# استخدمنا int() لتحويل النص إلى رقم
ADMIN_USER_ID = int(os.environ.get("ADMIN_USER_ID")) 
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN")
GITHUB_REPO = os.environ.get("GITHUB_REPO", "ihabmalaouiH/ULTRATV")
GITHUB_FILE_PATH = os.environ.get("GITHUB_FILE_PATH", "matches.json")
COMMIT_MESSAGE = "Auto-update matches list"

# التأكد من وجود التوكنز
if not BOT_TOKEN or not GITHUB_TOKEN or not ADMIN_USER_ID:
    print("خطأ: واحد أو أكثر من متغيرات البيئة (BOT_TOKEN, GITHUB_TOKEN, ADMIN_USER_ID) غير موجود.")
    # هذا السطر سيوقف البوت إذا لم يجد المفاتيح في Render
    exit(1) 

# --- 2. الكود الخاص بك (سحب البيانات وفك التشفير) ---
# (لا تغيير هنا)
def fetch_and_decrypt_matches():
    url = "https://a502.variety-buy.store/api/events"
    custom_headers = {
        'Accept': 'application/json',
        'User-Agent': 'okhttp/3.12.8',
        'api_url': 'http://ver3.yacinelive.com'
    }

    def xor_decrypt(encrypted_data, key):
        key_bytes = key.encode('utf-8')
        decrypted_bytes = bytearray()
        for encrypted_byte, key_byte in zip(encrypted_data, cycle(key_bytes)):
            decrypted_byte = encrypted_byte ^ key_byte
            decrypted_bytes.append(decrypted_byte)
        return decrypted_bytes

    try:
        response = requests.get(url, headers=custom_headers, timeout=10)
        if response.status_code != 200:
            print(f"فشل الطلب: {response.status_code}")
            return None
        if 't' not in response.headers:
            print("خطأ: الهيدر 't' غير موجود.")
            return None
        base64_data = response.text
        header_t_value = response.headers['t']
        key_part_1 = "c!xZj+N9&G@Ev@vw"
        full_key = key_part_1 + header_t_value
        encrypted_data = base64.b64decode(base64_data)
        decrypted_result = xor_decrypt(encrypted_data, full_key)
        decrypted_json_string = decrypted_result.decode('utf-8')
        cleaned_json_string = decrypted_json_string.replace(r"\/", "/")
        final_data = json.loads(cleaned_json_string)
        return final_data
    except Exception as e:
        print(f"حدث خطأ أثناء السحب: {e}")
        return None

# --- 3. دالة تحويل تنسيق JSON ---
# (لا تغيير هنا)
def transform_data(source_data):
    transformed_list = []
    if 'data' not in source_data or not isinstance(source_data['data'], list):
        print("خطأ: تنسيق البيانات المصدر غير متوقع.")
        return None
    for i, match in enumerate(source_data['data']):
        new_match = {
            "num": i + 1,
            "team1Name": match.get('team_1', {}).get('name', 'N/A'),
            "team1Logo": match.get('team_1', {}).get('logo', ''),
            "team2Name": match.get('team_2', {}).get('name', 'N/A'),
            "team2Logo": match.get('team_2', {}).get('logo', ''),
            "startTime": match.get('start_time', 0),
            "league": match.get('champions', 'N/A'),
            "channel": match.get('channel', 'N/A'),
            "commentator": match.get('commentary', 'N/A'),
            "servers": [] 
        }
        transformed_list.append(new_match)
    return transformed_list

# --- 4. دالة الرفع إلى GitHub ---
# (لا تغيير هنا)
def upload_to_github(json_data_string):
    api_url = f"https://api.github.com/repos/{GITHUB_REPO}/contents/{GITHUB_FILE_PATH}"
    headers = {
        "Authorization": f"token {GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json"
    }
    content_b64 = base64.b64encode(json_data_string.encode('utf-8')).decode('utf-8')
    try:
        r = requests.get(api_url, headers=headers, timeout=10)
        sha = r.json().get('sha') if r.status_code == 200 else None
    except Exception:
        sha = None
    data = {
        "message": COMMIT_MESSAGE,
        "content": content_b64,
        "committer": {"name": "Telegram Bot", "email": "bot@example.com"}
    }
    if sha:
        data['sha'] = sha
    try:
        r_put = requests.put(api_url, headers=headers, data=json.dumps(data), timeout=10)
        if r_put.status_code == 200 or r_put.status_code == 201:
            print("تم الرفع إلى GitHub بنجاح.")
            return True, r_put.json().get('content', {}).get('html_url', 'No URL')
        else:
            print(f"فشل الرفع إلى GitHub: {r_put.status_code} - {r_put.text}")
            return False, r_put.text
    except Exception as e:
        print(f"خطأ في الرفع: {e}")
        return False, str(e)

# --- 5. دوال البوت (Telegram Handlers) ---

def is_admin(update: Update):
    # نستخدم ADMIN_USER_ID الرقمي الذي قرأناه من Render
    return update.message.from_user.id == ADMIN_USER_ID

# (التصحيح: إضافة async)
async def start(update: Update, context: CallbackContext):
    if not is_admin(update): return
    # نستخدم .reply_text (وليس reply.text)
    await update.message.reply_text('أهلاً بك! أنا البوت الخاص بك. يتم الفحص تلقائياً كل 5 دقائق. استخدم /update للفحص اليدوي.')

# (التصحيح: إضافة async)
async def update_matches(update: Update, context: CallbackContext):
    if not is_admin(update): return
    msg = await update.message.reply_text('... جاري الفحص اليدوي ...')

    # استدعاء الدالة الأساسية للفحص
    # (نستخدم await لأننا سنقوم بإرسال رسائل منها)
    changes_found = await check_for_updates_and_upload(context)

    if changes_found is None:
        await msg.edit_text('حدث خطأ أثناء سحب البيانات من المصدر.')
    elif changes_found:
        await msg.edit_text('✅ تم الفحص اليدوي ووجدت تحديثات. تم الرفع.')
    else:
        await msg.edit_text('ℹ️ تم الفحص اليدوي. لا توجد تغييرات.')

# --- 6. (جديد) دالة جلب الملف القديم للمقارنة ---
# (لا تغيير هنا)
def get_current_github_data():
    """
    يجلب الملف الحالي من GitHub للمقارنة.
    """
    url = f"https://raw.githubusercontent.com/{GITHUB_REPO}/main/{GITHUB_FILE_PATH}"
    try:
        r = requests.get(url, timeout=10)
        if r.status_code == 200:
            return r.json() # إرجاع البيانات كـ JSON
        else:
            print("الملف غير موجود على GitHub بعد، سأعتبره فارغاً.")
            return None # الملف غير موجود
    except Exception as e:
        print(f"خطأ في جلب الملف القديم: {e}")
        return None

# --- 7. (جديد) دالة الفحص والمقارنة والرفع ---
# (التصحيح: إضافة async)
async def check_for_updates_and_upload(context: CallbackContext):
    """
    الدالة الأساسية التي تقوم بكل العمل.
    """
    print("بدء الفحص...")

    old_data = get_current_github_data()
    source_data = fetch_and_decrypt_matches()
    
    if not source_data:
        print("فشل سحب البيانات الجديدة.")
        return None 
    
    transformed_data = transform_data(source_data)
    
    if not transformed_data:
        print("فشل تحويل البيانات الجديدة.")
        return None 

    if old_data == transformed_data:
        print("لا توجد تغييرات.")
        return False 

    print("!!! تم اكتشاف تغييرات !!!")

    final_json_string = json.dumps(transformed_data, indent=2, ensure_ascii=False)
    success, result = upload_to_github(final_json_string)

    if success:
        print("تم الرفع بنجاح.")
        try:
            # (نستخدم await لأنها عملية غير متزامنة)
            await context.bot.send_message(
                chat_id=ADMIN_USER_ID, 
                text=f'✅ تحديث تلقائي ناجح!\n\nتم رصد تغييرات ورفعها إلى GitHub.\n{result}',
                disable_web_page_preview=True
            )
        except Exception as e:
            print(f"فشل إرسال رسالة تليجرام: {e}")
        return True 
    else:
        print("فشل الرفع.")
        try:
            # (نستخدم await)
            await context.bot.send_message(
                chat_id=ADMIN_USER_ID, 
                text=f'❌ فشل التحديث التلقائي!\n\nتم رصد تغييرات، ولكن فشل الرفع إلى GitHub.\nالخطأ: {result}'
            )
        except Exception as e:
            print(f"فشل إرسال رسالة تليجرام: {e}")
        return None 

# --- 8. (معدل) دالة تشغيل البوت والجدولة (v20.x) ---

def run_bot():
    """الدالة التي تشغل البوت"""
    application = Application.builder().token(BOT_TOKEN).build()
    
    job_queue = application.job_queue 

    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("update", update_matches)) 

    # interval=300 (5 دقائق).
    job_queue.run_repeating(check_for_updates_and_upload, interval=300, first=10)

    print("البوت قيد التشغيل...")
    print("سيتم الفحص التلقائي كل 5 دقائق.")
    application.run_polling()

# --- 9. (جديد) خادم الويب لإرضاء Render ---
app = Flask(__name__)

@app.route('/')
def hello_world():
    return 'البوت قيد التشغيل في الخلفية!'

def start_web_server():
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port)

# --- 10. (جديد) التنفيذ الرئيسي ---
if __name__ == '__main__':
    print("جاري تشغيل البوت في الخلفية...")
    bot_thread = threading.Thread(target=run_bot)
    bot_thread.daemon = True
    bot_thread.start()

    print("جاري تشغيل خادم الويب لربط المنفذ...")
    start_web_server()
