<?php
// تعيين رأس الصفحة لإعلام المتصفح أنه ملف JSON
header('Content-Type: application/json');

// --- ⭐️ الخطوة الأهم: التحقق من الدومين ⭐️ ---
// !! ⭐️ قم بتغيير هذا الرابط إلى رابط موقعك الرسمي ⭐️ !!
// مثال: 'ultra-tv-app.com' أو 'my-site.net'
$allowed_domain = 'ultrav.me'; 

// التحقق من "المرجع" (الموقع الذي طلب هذا الملف)
// هذا الكود يمنع المواقع الأخرى من سرقة الرابط
if (!isset($_SERVER['HTTP_REFERER']) || 
    stripos($_SERVER['HTTP_REFERER'], $allowed_domain) === false) {
    
    // إذا كان الطلب من موقع غير مصرح به، أرسل رسالة خطأ
    http_response_code(403); // إرسال رمز "ممنوع"
    echo json_encode(['error' => 'Unauthorized Access']);
    exit; // إيقاف التنفيذ
}
// --- نهاية خطوة التحقق ---


// ⭐️ هنا تضع الروابط والمفاتيح السرية
// هذه البيانات لن تظهر أبداً في "عرض المصدر" لملف HTML
$stream_data = [
    "file" => "https://prod-fastly-eu-central-1.video.pscp.tv/Transcoding/v1/hls/6mavWS5PNXXNq-U2m_nv3LZkirzlwAr9tsn1EHoWAkApUQzqDLg2tiIJds94YnV4S12NjUhhySCNayxRsmTNRQ/non_transcode/eu-central-1/periscope-replay-direct-prod-eu-central-1-public/master_dynamic_highlatency.m3u8?type=live",
    "drm" => [
        "clearkey" => [
            "keyId" => "d84c325f36814f39bbe59080272b10c3",
            "key" => "550727de4c96ef1ecff874905493580f"
        ]
    ]
];

// إرسال البيانات كـ JSON إلى المشغل
echo json_encode($stream_data);
?>
