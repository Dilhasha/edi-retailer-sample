import ballerina/ftp;
import ballerina/io;
import ballerina/log;
import ballerina/sql;

listener ftp:Listener invoiceListener = new (protocol = ftp:SFTP, host = ftpHost, port = ftpPort, auth = {
    credentials: {
        username: ftpUsername,
        password: ftpPassword
    }
}, path = ftpInvoiceLocation, fileNamePattern = ftpFilePattern, pollingInterval = ftpPollingInterval);

service ftp:Service on invoiceListener {
    remote function onFileChange(ftp:WatchEvent & readonly event, ftp:Caller caller) returns error? {
        do {
            foreach ftp:FileInfo addedFile in event.addedFiles {
                log:printInfo("Received file " + addedFile.name);
                stream<byte[] & readonly, io:Error?> inStream = check ftpClient->get(addedFile.pathDecoded);
                string content = "";
                check inStream.forEach(function(byte[] & readonly data) {
                    string|error chunk = string:fromBytes(data);
                    if (chunk is error) {
                        log:printError("Error converting bytes to string: " + chunk.message());
                        return;
                    }
                    content += chunk;
                    // Process the file data
                });
                log:printInfo("file content: " + content);
                Invoice invoice = check fromEdiString(content);
                InvoiceDetails invoiceDetails = transform(invoice);
                sql:ExecutionResult sqlExecutionresult = check mysqlClient->execute(`INSERT INTO Invoices (invoiceId, amount, paymentStatus) VALUES (${invoiceDetails.invoiceId}, ${invoiceDetails.amount}, ${invoiceDetails.paymentStatus})`);
                if sqlExecutionresult.affectedRowCount == 1 {
                    log:printInfo("Inserted the invoice details for " + invoiceDetails.invoiceId.toString());
                }
            }

        } on fail error err {
            // handle error
            return error("unhandled error", err);
        }
    }
}
