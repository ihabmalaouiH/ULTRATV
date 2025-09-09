import requests, json
from datetime import datetime

API_KEY = "a42e10c9521e21e90a8845a1a36e998f"
URL = "https://v3.football.api-sports.io/fixtures"

# البطولات المهمة (تقدر تغير الأرقام)
IMPORTANT_LEAGUES = [2, 39, 140, 78]

headers = {"x-apisports-key": API_KEY}
today = datetime.today().strftime("%Y-%m-%d")

params = {
    "date": today,
    "league": ",".join(map(str, IMPORTANT_LEAGUES))
}

res = requests.get(URL, headers=headers, params=params)
matches = []

if res.status_code == 200:
    data = res.json()
    for fx in data.get("response", []):
        matches.append({
            "competition": fx["league"]["name"],
            "home": fx["teams"]["home"]["name"],
            "away": fx["teams"]["away"]["name"],
            "time": fx["fixture"]["date"],
            "status": fx["fixture"]["status"]["short"]
        })

output = {"date": today, "matches": matches}

with open("matches.json", "w", encoding="
