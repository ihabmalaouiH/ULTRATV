const axios = require('axios');
const fs = require('fs');

// --- Configuration ---
const API_KEY = process.env.API_SPORTS_KEY;
const API_HOST = 'v3.football.api-sports.io';

// --- Add the League IDs you consider important ---
const IMPORTANT_LEAGUE_IDS = [39, 140, 135, 78, 61, 2, 3]; // Premier League, La Liga, Champions League, etc.

async function fetchImportantMatches() {
    if (!API_KEY) {
        console.error("ERROR: API_SPORTS_KEY secret is not set in your repository settings.");
        return;
    }

    const today = new Date();
    const dateString = `${today.getFullYear()}-${(today.getMonth() + 1).toString().padStart(2, '0')}-${today.getDate().toString().padStart(2, '0')}`;
    
    console.log(`Fetching important matches for ${dateString}...`);
    const allMatches = [];

    for (const leagueId of IMPORTANT_LEAGUE_IDS) {
        try {
            const response = await axios.get('https://v3.football.api-sports.io/fixtures', {
                headers: { 'x-rapidapi-host': API_HOST, 'x-rapidapi-key': API_KEY },
                params: { league: leagueId, season: today.getFullYear(), date: dateString }
            });

            if (response.data.errors && Object.keys(response.data.errors).length > 0) {
                console.error(`API Error for league ${leagueId}:`, JSON.stringify(response.data.errors));
            }

            if (response.data.response && response.data.response.length > 0) {
                allMatches.push(...response.data.response);
            }
        } catch (error) {
            // This now prints a much more detailed error message
            console.error(`Error fetching matches for league ${leagueId}:`, error.response ? JSON.stringify(error.response.data) : error.message);
        }
    }
    
    if (allMatches.length === 0) {
        console.log("\nNo important matches found for today in the specified leagues.");
    }

    const simplifiedMatches = allMatches.map(fixture => ({
        team1Name: fixture.teams.home.name, team1Logo: fixture.teams.home.logo,
        team2Name: fixture.teams.away.name, team2Logo: fixture.teams.away.logo,
        status: fixture.fixture.status.long, league: fixture.league.name,
        score: `${fixture.goals.home ?? ''} - ${fixture.goals.away ?? ''}`,
        startTime: fixture.fixture.timestamp,
        isLive: ['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'].includes(fixture.fixture.status.short),
    }));

    fs.writeFileSync('matches.json', JSON.stringify(simplifiedMatches, null, 2));
    console.log(`\nSuccessfully updated matches.json with ${simplifiedMatches.length} matches.`);
}

fetchImportantMatches();
