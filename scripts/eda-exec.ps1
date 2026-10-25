$body = '{"code":"return await eda.dmt_Project.getCurrentProjectInfo();"}'
curl.exe -s -X POST http://localhost:49620/execute -H "Content-Type: application/json" -d $body
