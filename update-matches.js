const axios = require('axios');
const fs = require('fs');

// --- Configuration ---
// Your API key will be securely provided by GitHub Actions
const API_KEY = process.env.API_SPORTS_KEY;
const API_HOST = 'v3.football.api-sports.io';

// --- Add the League IDs you consider important ---
// Example IDs: 39=Premier League, 140=La Liga, 135=Serie A, 78=Bundesliga, 61=Ligue 1, 2=Champions League
const IMPORTANT_LEAGUE_IDS = [39, 140, 135, 78, 61, 2, 3];

async function fetchImportantMatches() {
    const today = new Date();
    const dateString = `${today.getFullYear()}-${(today.getMonth() + 1).toString().padStart(2, '0')}-${today.getDate().toString().padStart(2, '0')}`;
    
    console.log(`Fetching important matches for ${dateString}...`);
    const allMatches = [];

    for (const leagueId of IMPORTANT_LEAGUE_IDS) {
        try {
            const response = await axios.get('https://v3.football.api-sports.io/fixtures', {
                headers: {
                    'x-rapidapi-host': API_HOST,
                    'x-rapidapi-key': API_KEY
                },
                params: {
                    league: leagueId,
                    season: today.getFullYear(),
                    date: dateString
                }
            });

            if (response.data.response && response.data.response.length > 0) {
                allMatches.push(...response.data.response);
                console.log(`Found ${response.data.response.length} matches for league ${leagueId}.`);
            }
        } catch (error) {
            console.error(`Error fetching matches for league ${leagueId}:`, error.message);
        }
    }

    // This part simplifies the data to match what your app needs
    const simplifiedMatches = allMatches.map(fixture => ({
        team1Name: fixture.teams.home.name,
        team1Logo: fixture.teams.home.logo,
        team2Name: fixture.teams.away.name,
        team2Logo: fixture.teams.away.logo,
        status: fixture.fixture.status.long,
        league: fixture.league.name,
        score: `${fixture.goals.home ?? ''} - ${fixture.goals.away ?? ''}`,
        startTime: fixture.fixture.timestamp,
        isLive: ['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'].includes(fixture.fixture.status.short),
    }));

    // Save the final data to the matches.json file
    fs.writeFileSync('matches.json', JSON.stringify(simplifiedMatches, null, 2));
    console.log(`Successfully updated matches.json with ${simplifiedMatches.length} matches.`);
}

fetchImportantMatches();
