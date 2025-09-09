const axios = require('axios');
const fs = require('fs');

// --- Configuration ---
const API_KEY = process.env.API_SPORTS_KEY; // We will get this from GitHub Secrets
const API_HOST = 'v3.football.api-sports.io';

// Add the IDs of the leagues you consider "important"
// Example: 39=Premier League, 140=La Liga, 135=Serie A, 78=Bundesliga, 61=Ligue 1, 2=Champions League
const IMPORTANT_LEAGUE_IDS = [39, 140, 135, 78, 61, 2, 3];

async function fetchImportantMatches() {
    const today = new Date();
    const dateString = `${today.getFullYear()}-${(today.getMonth() + 1).toString().padStart(2, '0')}-${today.getDate().toString().padStart(2, '0')}`;
    
    const allMatches = [];

    for (const leagueId of IMPORTANT_LEAGUE_IDS) {
        try {
            const response = await axios.get(`https://v3.football.api-sports.io/fixtures`, {
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

            if (response.data.response) {
                allMatches.push(...response.data.response);
            }
        } catch (error) {
            console.error(`Error fetching matches for league ${leagueId}:`, error.message);
        }
    }

    // Simplify the data for our app
    const simplifiedMatches = allMatches.map(fixture => ({
        team1Name: fixture.teams.home.name,
        team1Logo: fixture.teams.home.logo,
        team2Name: fixture.teams.away.name,
        team2Logo: fixture.teams.away.logo,
        status: fixture.fixture.status.short,
        league: fixture.league.name,
        score: `${fixture.goals.home ?? ''} - ${fixture.goals.away ?? ''}`,
        startTime: fixture.fixture.timestamp,
        isLive: ['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'].includes(fixture.fixture.status.short),
    }));

    // Save the data to matches.json
    fs.writeFileSync('matches.json', JSON.stringify(simplifiedMatches, null, 2));
    console.log('matches.json has been updated successfully.');
}

fetchImportantMatches();
