use serde_json::{Map, Value, json};
use std::time::Duration;

pub const PRODUCTION: &str = "https://firestore.googleapis.com";

pub fn string(value: &str) -> Value {
    json!({ "stringValue": value })
}

pub fn integer(value: i64) -> Value {
    json!({ "integerValue": value.to_string() })
}

pub fn timestamp(iso: &str) -> Value {
    json!({ "timestampValue": iso })
}

fn decode_value(value: &Value) -> Value {
    let Some(typed) = value.as_object() else {
        return Value::Null;
    };
    if let Some(s) = typed.get("stringValue").or(typed.get("timestampValue")) {
        return s.clone();
    }
    if let Some(n) = typed.get("integerValue") {
        let parsed = n.as_str().and_then(|s| s.parse::<i64>().ok());
        return parsed.map_or(Value::Null, Value::from);
    }
    ["doubleValue", "booleanValue"]
        .iter()
        .find_map(|key| typed.get(*key))
        .cloned()
        .unwrap_or(Value::Null)
}

pub fn decode_fields(fields: &Value) -> Value {
    let plain: Map<String, Value> = fields
        .as_object()
        .into_iter()
        .flatten()
        .map(|(key, value)| (key.clone(), decode_value(value)))
        .collect();
    Value::Object(plain)
}

pub struct Firestore {
    agent: ureq::Agent,
    documents: String,
}

enum Method {
    Post,
    Patch,
    Delete,
}

impl Firestore {
    pub fn new(base_url: &str, project: &str) -> Self {
        let agent = ureq::Agent::config_builder()
            .http_status_as_error(false)
            .timeout_global(Some(Duration::from_secs(30)))
            .build()
            .into();
        Self {
            agent,
            documents: format!(
                "{}/v1/projects/{project}/databases/(default)/documents",
                base_url.trim_end_matches('/')
            ),
        }
    }

    fn send(
        &self,
        method: Method,
        url: &str,
        token: &str,
        body: Option<&Value>,
    ) -> Result<(u16, String), String> {
        let auth = format!("Bearer {token}");
        let result = match (method, body) {
            (Method::Post, Some(body)) => self
                .agent
                .post(url)
                .header("Authorization", &auth)
                .send_json(body),
            (Method::Patch, Some(body)) => self
                .agent
                .patch(url)
                .header("Authorization", &auth)
                .send_json(body),
            _ => self.agent.delete(url).header("Authorization", &auth).call(),
        };
        let mut response = result.map_err(|e| format!("network: {e}"))?;
        let status = response.status().as_u16();
        let text = response.body_mut().read_to_string().unwrap_or_default();
        Ok((status, text))
    }

    fn http_error(status: u16, body: &str) -> String {
        let detail: String = body.chars().take(300).collect();
        format!("Firestore HTTP {status}: {detail}")
    }

    pub fn open_requests(
        &self,
        token: &str,
        cutoff_iso: &str,
    ) -> Result<Vec<(String, Value)>, String> {
        let query = json!({ "structuredQuery": {
            "from": [{ "collectionId": "assistantRequests" }],
            "where": { "fieldFilter": {
                "field": { "fieldPath": "requestedAt" },
                "op": "GREATER_THAN_OR_EQUAL",
                "value": string(cutoff_iso),
            }},
            "orderBy": [{ "field": { "fieldPath": "requestedAt" }, "direction": "ASCENDING" }],
            "limit": 20,
        }});
        let url = format!("{}:runQuery", self.documents);
        let (status, body) = self.send(Method::Post, &url, token, Some(&query))?;
        if status != 200 {
            return Err(Self::http_error(status, &body));
        }
        let rows: Value = serde_json::from_str(&body).map_err(|e| e.to_string())?;
        Ok(rows
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|row| {
                let doc = row.get("document")?;
                let name = doc.get("name")?.as_str()?;
                let id = name.rsplit('/').next()?.to_string();
                Some((id, decode_fields(doc.get("fields")?)))
            })
            .collect())
    }

    pub fn claim(&self, token: &str, id: &str, fields: &Value) -> Result<bool, String> {
        let url = format!(
            "{}/assistantRequests/{id}?updateMask.fieldPaths=claimedBy\
             &updateMask.fieldPaths=claimedAt&currentDocument.exists=true",
            self.documents
        );
        let (status, body) = self.send(
            Method::Patch,
            &url,
            token,
            Some(&json!({ "fields": fields })),
        )?;
        match status {
            200 => Ok(true),
            404 => Ok(false),
            _ => Err(Self::http_error(status, &body)),
        }
    }

    pub fn write_summary(&self, token: &str, id: &str, fields: &Value) -> Result<(), String> {
        let url = format!("{}/assistantSummaries/{id}", self.documents);
        let (status, body) = self.send(
            Method::Patch,
            &url,
            token,
            Some(&json!({ "fields": fields })),
        )?;
        match status {
            200 => Ok(()),
            _ => Err(Self::http_error(status, &body)),
        }
    }

    pub fn delete_request(&self, token: &str, id: &str) -> Result<(), String> {
        let url = format!("{}/assistantRequests/{id}", self.documents);
        let (status, body) = self.send(Method::Delete, &url, token, None)?;
        match status {
            200 | 404 => Ok(()),
            _ => Err(Self::http_error(status, &body)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_the_value_types_the_queue_uses() {
        let fields = json!({
            "a": { "stringValue": "x" },
            "b": { "integerValue": "42" },
            "c": { "timestampValue": "2026-11-10T00:00:00Z" },
            "d": { "booleanValue": true },
            "e": { "mapValue": {} },
        });
        let plain = decode_fields(&fields);
        assert_eq!(plain["a"], "x");
        assert_eq!(plain["b"], 42);
        assert_eq!(plain["c"], "2026-11-10T00:00:00Z");
        assert_eq!(plain["d"], true);
        assert_eq!(plain["e"], Value::Null);
    }

    #[test]
    fn builds_the_documents_url_for_a_project() {
        let fs = Firestore::new("http://localhost:1/", "p");
        assert_eq!(
            fs.documents,
            "http://localhost:1/v1/projects/p/databases/(default)/documents"
        );
    }
}
