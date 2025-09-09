import requests
import json
from datetime import date

API_KEY = "a42e10c9521e21e90a8845a1a36e998f"
url = "https://v3.football.api-sports.io/fixtures"

params = {
    "date": date.today().strftime("%Y-%m-%d"),  # مباريات اليوم
    "timezone": "Africa/Algiers",              # التوقيت المحلي
    "league": "2,3,39,140,135,78,61"           # البطولات المهمة (دوري أبطال، إنجليزي، إسباني...)
}

headers = {
    "x-apisports-key": API_KEY
}

r = requests.get(url, headers=headers, params=params)
