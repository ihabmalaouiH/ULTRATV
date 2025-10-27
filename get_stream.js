// هذا هو ملف "الدالة السحابية" (Serverless Function)
// إنه بديل ملف get_stream.php
// المسار: /api/get_stream.js

export default function handler(request, response) {
    
    // --- ⭐️ الخطوة الأهم: التحقق من الدومين ⭐️ ---
    // !! ⭐️ قم بتغيير هذا الرابط إلى رابط موقعك الرسمي ⭐️ !!
    // مثال: 'ultra-tv-app.vercel.app' أو 'my-site.net'
    const allowedDomain = 'YOUR-WEBSITE-DOMAIN.com';
    
    // Vercel تستخدم 'x-forwarded-host' أو 'host'
    // Netlify تستخدم 'host'
    const host = request.headers['x-forwarded-host'] || request.headers['host'];

    // التحقق من أن الطلب قادم من الدومين المسموح به
    if (!host || !host.includes(allowedDomain)) {
        // إذا كان الطلب من موقع غير مصرح به، أرسل رسالة خطأ
        return response.status(403).json({ error: 'Unauthorized Access' });
    }
    // --- نهاية خطوة التحقق ---


    // ⭐️ هنا تضع الروابط والمفاتيح السرية
    const streamData = {
        file: "https://prod-fastly-eu-central-1.video.pscp.tv/Transcoding/v1/hls/6mavWS5PNXXNq-U2m_nv3LZkirzlwAr9tsn1EHoWAkApUQzqDLg2tiIJds94YnV4S12NjUhhySCNayxRsmTNRQ/non_transcode/eu-central-1/periscope-replay-direct-prod-eu-central-1-public/master_dynamic_highlatency.m3u8?type=live",
        drm: {
            clearkey: {
                keyId: "d84c325f36814f39bbe59080272b10c3",
                key: "550727de4c96ef1ecff874905493580f"
            }
        }
    };

    // إرسال البيانات كـ JSON إلى المشغل
    // مع إضافة "Cache-Control" لضمان جلب البيانات حديثة
    response.setHeader('Cache-Control', 's-maxage=1, stale-while-revalidate');
    return response.status(200).json(streamData);
}
