# Document OCR Service

Cloud Run URL:

```text
https://document-ocr-fnmzxhthpq-as.a.run.app
```

Health check:

```powershell
curl.exe https://document-ocr-fnmzxhthpq-as.a.run.app/health
```

Get the API key from Secret Manager:

```powershell
$env:OCR_API_KEY = gcloud secrets versions access latest `
  --secret=document-ocr-api-key `
  --project=tangentx
```

OCR a PDF or scanned image:

```powershell
curl.exe -X POST "https://document-ocr-fnmzxhthpq-as.a.run.app/ocr" `
  -H "X-API-Key: $env:OCR_API_KEY" `
  -F "file=@C:\path\to\document.pdf;type=application/pdf"
```

Runtime details:

- Google Cloud project: `tangentx`
- Cloud Run service: `document-ocr`
- Cloud Run region: `asia-southeast1`
- Document AI location: `us`
- Document AI processor ID: `17a7cd12aa918283`
- Secret Manager secret: `document-ocr-api-key`
