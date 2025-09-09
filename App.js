import express from "express";
import fetch from "node-fetch";
import * as cheerio from "cheerio";

const app = express();

app.get("/api/matches", async (req, res) => {
  try {
    const response = await fetch("https://jdwel.com/");
    const html = await response.text();
    const $ = cheerio.load(html);

    let matches = [];

    $(".match-card").each((i, el) => {
      const competition = $(el).find(".competition-name").text().trim();
      const home = $(el).find(".team-home .team-name").text().trim();
      const away = $(el).find(".team-away .team-name").text().trim();
      const time = $(el).find(".match-time").text().trim();
      const status = $(el).find(".match-status").text().trim();

      if (home && away) {
        matches.push({ competition, home, away, time, status });
      }
    });

    res.json({
      date: new Date().toISOString().slice(0, 10),
      matches
    });

  } catch (err) {
    res.status(500).json({ error: "فشل الجلب", details: err.message });
  }
});

app.listen(3000, () => console.log("✅ API يعمل على http://localhost:3000/api/matches"));
