# AI Watch Tower

This repository contains an n8n workflow for monitoring and summarizing the latest news from major AI companies.

![AI Watch Tower Workflow](https://github.com/bluebeckie/beckie-n8n/blob/main/AI-WatchTower/AI-Watch-Tower.png)

## Workflow Actions

This n8n workflow automates the process of fetching, processing, and delivering the latest news about AI from multiple sources. The workflow is designed to run on a schedule and send a summarized report to a LINE chat.

Here is a breakdown of the workflow's key actions:

1.  **Scheduled Trigger**: The workflow is initiated by a schedule, running automatically at predefined intervals to ensure the news is always up-to-date.

2.  **URL Definition**: A set of initial URLs are defined for the different news sources. This can be manually updated.

3.  **Parallel Fetching**: The workflow fetches news from three different sources in parallel:
    *   OpenAI's news feed (XML).
    *   Google Gemini's news (HTML).
    *   Anthropic's news (HTML).

4.  **News Extraction**: For each source, an AI agent (using OpenAI's Chat Model) is used to extract structured news data, including titles, URLs, and publication dates.

5.  **Source Merging**: The extracted news items from all three sources are merged into a single list for unified processing.

6.  **Filtering and Date Conversion**: The merged list is then filtered to remove any irrelevant items, and the publication dates are converted to a consistent format.

7.  **Conditional Summarization**: An "If" node checks if there are any news items to be processed.
    *   If there is news, the items are passed to a summarization agent that uses the Google Gemini Chat Model to create a concise summary of all the collected news.
    *   The links from the news items are then joined together.

8.  **LINE Messaging**: The final summarized news report, along with the joined links, is sent as a message to a specified LINE chat. If there was no news to process, a different message is sent.
