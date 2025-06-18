import ballerina/ftp;
import ballerina/io;
import ballerina/log;
import ballerina/sql;

listener ftp:Listener ftpListener = new (protocol = ftp:SFTP, host = ftpHost, port = ftpPort, auth = {
    credentials: {
        username: ftpUsername,
        password: ftpPassword
    }
}, path = ftpInvoiceLocation, fileNamePattern = ftpFilePattern, pollingInterval = ftpPollingInterval);

service ftp:Service on ftpListener {
    remote function onFileChange(ftp:WatchEvent & readonly event, ftp:Caller caller) returns error? {
        do {
            foreach ftp:FileInfo addedFile in event.addedFiles {
                log:printInfo("Received file " + addedFile.pathDecoded);
                stream<byte[] & readonly, io:Error?> inStream = check ftpClient->get(addedFile.pathDecoded);
                string content = "";
                check inStream.forEach(function(byte[] & readonly data) {
                    string|error chunk = string:fromBytes(data);
                    if chunk is error {
                        log:printError("Error converting bytes to string: " + chunk.message());
                        return;
                    }
                    content += chunk;
                });
                log:printInfo("Received file content " + content);
                Invoice invoice = check fromEdiString(content);
                InvoiceDetails invoiceDetails = transform(invoice);
                log:printInfo("Received invoice details for invoice id " + (invoiceDetails.invoiceId ?: ""));
                sql:ExecutionResult sqlExecutionresult = check mysqlClient->execute(`INSERT INTO Invoices (invoiceId, amount, paymentStatus) VALUES (${invoiceDetails.invoiceId}, ${invoiceDetails.amount}, ${invoiceDetails.paymentStatus})`);
                if sqlExecutionresult.affectedRowCount == 1 {
                    log:printInfo("Successfully inserted the invoice details to database for the invoice " + (invoiceDetails.invoiceId ?: ""));
                }
            }
        } on fail error err {
            // handle error
            return error("unhandled error", err);
        }
    }
}