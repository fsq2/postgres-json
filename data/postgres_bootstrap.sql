-- Content catalogue ----------------------------------------------
CREATE TABLE content (
    id              UUID PRIMARY KEY,
    slug            TEXT UNIQUE NOT NULL,
    title           TEXT        NOT NULL,
    content_type    TEXT CHECK (content_type IN ('podcast', 'newsletter', 'video')),
    length_seconds  INTEGER, 
    publish_ts      TIMESTAMPTZ NOT NULL
);

-- Raw engagement telemetry ---------------------------------------
CREATE TABLE engagement_events (
    id           BIGSERIAL PRIMARY KEY,
    content_id   UUID REFERENCES content(id),
    user_id      UUID,
    event_type   TEXT CHECK (event_type IN ('play', 'pause', 'finish', 'click')),
    event_ts     TIMESTAMPTZ NOT NULL,
    duration_ms  INTEGER,      -- nullable for events without duration
    device       TEXT,         -- e.g. "ios", "web‑safari"
    raw_payload  JSONB         -- anything extra the client sends
);


INSERT INTO content (id, slug, title, content_type, length_seconds, publish_ts) VALUES
('b30d321d-9e0c-45b9-92c4-8f7a6f23c72a', 'episode-1-data-catalogue', 'Building a Data Catalogue', 'podcast', 1800, '2023-01-15 10:00:00+00'),
('f58a71c8-8a9d-4e5b-b9f1-3d7c58d0e70a', 'video-how-to-use-sql', 'SQL for Beginners: A Quick Guide', 'video', 900, '2023-05-20 14:45:00+00');


INSERT INTO engagement_events (content_id, user_id, event_type, event_ts, duration_ms, device, raw_payload) VALUES
('b30d321d-9e0c-45b9-92c4-8f7a6f23c72a', '8c9b0e11-4d56-4b8c-8f9f-0e1c2d3b4a5f', 'play', '2023-01-15 10:01:05+00', 60000, 'ios', '{"source": "search"}'),
('b30d321d-9e0c-45b9-92c4-8f7a6f23c72a', '8c9b0e11-4d56-4b8c-8f9f-0e1c2d3b4a5f', 'finish', '2023-01-15 10:30:15+00', NULL, 'ios', '{"source": "search", "completed": true}');

