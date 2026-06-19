#!/usr/bin/env node
import {
  createConnection,
  ProposedFeatures,
  TextDocuments,
  TextDocumentSyncKind,
  type Hover,
  type InitializeResult
} from "vscode-languageserver/node";
import { TextDocument } from "vscode-languageserver-textdocument";

import { hoverAtPosition } from "./hover.js";

const connection = createConnection(ProposedFeatures.all, process.stdin, process.stdout);
const documents = new TextDocuments(TextDocument);

connection.onInitialize(
  (): InitializeResult => ({
    capabilities: {
      hoverProvider: true,
      textDocumentSync: TextDocumentSyncKind.Incremental
    },
    serverInfo: {
      name: "wat-lsp",
      version: "0.0.0"
    }
  })
);

connection.onHover(async ({ position, textDocument }): Promise<Hover | null> => {
  const document = documents.get(textDocument.uri);
  if (!document) {
    return null;
  }

  return hoverAtPosition(document.getText(), position);
});

documents.listen(connection);
connection.listen();
