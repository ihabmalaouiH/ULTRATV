import express from "express";
import fetch from "node-fetch";

const app = express();
const PORT = process.env.PORT || 3000;

// قائمة القنوات الناقلة (تضيفها حسب ما تحب)
const channels = [
  { name: "beIN SPORTS 1", logoUrl: "assets/logos/bein1.png" },
  { name: "beIN SPORTS 2", logoUrl: "assets/logos/bein2.png" },
  { name: "SSC 1", logoUrl: "assets/logos/ssc1.png" }
];

// دالة تجيب المباريات من SofaScore
async function getMatches() {
  const url = "https://api.sofascore.com/api/v1/sport/football/scheduled-events";
  const response = await fetch(url);
  const data = await response.json();

  // نحول البيانات لشكل منظم
  const matches = data.events.map(event => ({
    league: event.tournament.name,
    home: event.homeTeam.name,
    away: event.awayTeam.name,
    time: new Date(event.startTimestamp * 1000).toISOString(),
    channels: channels // نفس القنوات لكل مباراة (تقدر تغيرها لاحقاً)
  }));

  return matches;
}

// API Endpoint
app.get("/matches", async (req, res) => {
  try {
    const matches = await getMatches();
    res.json(matches);
  } catch (error) {
    res.status(500).json({ error: "خطأ في جلب البيانات" });
  }
});

app.listen(PORT, () => {
  console.log(`✅ API شغّال على http://localhost:${PORT}`);
});
