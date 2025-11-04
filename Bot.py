import requests
import base64
from itertools import cycle
import json
import logging
import time
from telegram import Update
from telegram.ext import Updater, CommandHandler, CallbackContext

# --- 1. إعدادات التليجرام وجيت هاب (الرجاء ملء هذه) ---

# !!! تحذير: لا تنشر هذه المفاتيح علناً !!!
# (استخدم مفاتيح جديدة بعد أن قمت بإلغاء القديمة)
BOT_TOKEN = "8407076175:AAHPF-CCGLEkqaC6Srydl3Iu6rbHhf6XK8Y" 
ADMIN_USER_ID = 8421187425 # هذا حسابك
GITHUB_TOKEN = "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"
GITHUB_REPO = "ihabmalaouiH/ULTRATV"
GITHUB_FILE_PATH = "matches.json"
COMMIT_MESSAGE = "Auto-update matches list"

# --- 2. الكود الخاص بك (سحب البيانات وفك التشفير) ---
# (لا تغيير هنا، تم نسخها كما هي)
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
# (لا تغيير هنا)
def is_admin(update: Update):
    return update.message.from_user.id == ADMIN_USER_ID

def start(update: Update, context: CallbackContext):
    if not is_admin(update): return
    update.message.reply_text('أهلاً بك! أنا البوت الخاص بك. يتم الفحص تلقائياً كل 5 دقائق. استخدم /update للفحص اليدوي.')

def update_matches(update: Update, context: CallbackContext):
    if not is_admin(update): return
    msg = update.message.reply_text('... جاري الفحص اليدوي ...')

    # استدعاء الدالة الأساسية للفحص
    changes_found = check_for_updates_and_upload(context)

    if changes_found is None:
        msg.edit_text('حدث خطأ أثناء سحب البيانات من المصدر.')
    elif changes_found:
        msg.edit_text('✅ تم الفحص اليدوي ووجدت تحديثات. تم الرفع.')
    else:
        msg.edit_text('ℹ️ تم الفحص اليدوي. لا توجد تغييرات.')

# --- 6. (جديد) دالة جلب الملف القديم للمقارنة ---
def get_current_github_data():
    """
    يجلب الملف الحالي من GitHub للمقارنة.
    """
    # نستخدم raw.githubusercontent.com للقراءة المباشرة
    # افترضت أن الفرع (branch) هو 'main'. غيّره إذا كان اسم الفرع مختلفاً.
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
def check_for_updates_and_upload(context: CallbackContext):
    """
    الدالة الأساسية التي تقوم بكل العمل:
    1. تجلب البيانات القديمة من GitHub.
    2. تجلب البيانات الجديدة من الـ API.
    3. تقارن بينهما.
    4. ترفع إذا كان هناك اختلاف.
    5. ترسل رسالة للـ Admin إذا نجح الرفع.
    """
    print("بدء الفحص...")

    # 1. جلب البيانات القديمة
    old_data = get_current_github_data()

    # 2. جلب البيانات الجديدة
    source_data = fetch_and_decrypt_matches()
    if not source_data:
        print("فشل سحب البيانات الجديدة.")
        return None # إشارة لوجود خطأ

    transformed_data = transform_data(source_data)
    if not transformed_data:
        print("فشل تحويل البيانات الجديدة.")
        return None # إشارة لوجود خطأ

    # 3. المقارنة (هذا هو طلبك الأساسي)
    if old_data == transformed_data:
        print("لا توجد تغييرات.")
        return False # إشارة لعدم وجود تغيير

    print("!!! تم اكتشاف تغييرات !!!")

    # 4. الرفع (لأن البيانات مختلفة)
    final_json_string = json.dumps(transformed_data, indent=2, ensure_ascii=False)
    success, result = upload_to_github(final_json_string)

    if success:
        print("تم الرفع بنجاح.")
        # 5. إرسال إشعار للـ Admin
        try:
            context.bot.send_message(
                chat_id=ADMIN_USER_ID, 
                text=f'✅ تحديث تلقائي ناجح!\n\nتم رصد تغييرات ورفعها إلى GitHub.\n{result}',
                disable_web_page_preview=True
            )
        except Exception as e:
            print(f"فشل إرسال رسالة تليجرام: {e}")
        return True # إشارة لوجود تغيير
    else:
        print("فشل الرفع.")
        try:
            context.bot.send_message(
                chat_id=ADMIN_USER_ID, 
                text=f'❌ فشل التحديث التلقائي!\n\nتم رصد تغييرات، ولكن فشل الرفع إلى GitHub.\nالخطأ: {result}'
            )
        except Exception as e:
            print(f"فشل إرسال رسالة تليجرام: {e}")
        return None # إشارة لوجود خطأ

# --- 8. (معدل) دالة تشغيل البوت والجدولة ---
# --- 8. (معدل) دالة تشغيل البوت والجدولة (بإصدار v20.x) ---

# قم بإضافة هذا السطر في أعلى الملف مع باقي الـ imports
from telegram.ext import Application 

def main():
    # 1. طريقة الإنشاء الجديدة (بدون use_context)
    application = Application.builder().token(BOT_TOKEN).build()

    # 2. الوصول إلى الجدولة
    job_queue = application.job_queue 

    # 3. إضافة الأوامر اليدوية
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("update", update_matches)) 

    # 4. إضافة المؤقت (الفحص التلقائي)
    # interval=300 (5 دقائق).
    job_queue.run_repeating(check_for_updates_and_upload, interval=300, first=10)

    # 5. تشغيل البوت
    print("البوت قيد التشغيل...")
    print("سيتم الفحص التلقائي كل 5 دقائق.")
    application.run_polling()

# --- (جديد) خادم الويب لإرضاء Render ---
app = Flask(__name__)

@app.route('/')
def hello_world():
    # هذه الصفحة تثبت فقط أن الخدمة تعمل
    return 'البوت قيد التشغيل في الخلفية!'

def start_web_server():
    # Render سيوفر متغير PORT تلقائياً
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port)

# --- (جديد) التنفيذ الرئيسي ---
if __name__ == '__main__':
    # 1. تشغيل البوت (الذي غيرنا اسمه إلى run_bot) في "ثريد" منفصل
    print("جاري تشغيل البوت في الخلفية...")
    bot_thread = threading.Thread(target=run_bot)
    bot_thread.daemon = True
    bot_thread.start()

    # 2. تشغيل خادم الويب (هذا ما يحتاجه Render ليبقى سعيداً)
    print("جاري تشغيل خادم الويب لربط المنفذ...")
    start_web_server()
