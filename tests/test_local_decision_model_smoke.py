"""Optional installed-ONNX probe of the author's article Choice example.

This checks whether a game-probe failure could simply be a dead/miswired head.
It is an experiment, not a dependency of the game's CI or an accuracy guarantee.
"""
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/ai"))
from bekko_backend import BekkoBackend

def main():
    size = "68" if len(sys.argv) > 1 and sys.argv[1] == "68" else "17"
    with BekkoBackend(size) as model:
        np = model.np
        encode = lambda text: model.tokenizer.encode(text, add_special_tokens=False).ids
        manifest = model.manifest
        ids = ["sports", "business"]
        documents = [encode("Candidate: sports: Sports news about players and competitions.") + [manifest["sep_token_id"]],
                     encode("Candidate: business: Business news about companies and money.") + [manifest["sep_token_id"]]]
        width = max(map(len, documents))
        doc_ids = np.full((2, width), manifest["pad_token_id"], dtype=np.int64)
        doc_mask = np.zeros(doc_ids.shape, dtype=np.bool_)
        for row, tokens in enumerate(documents):
            doc_ids[row, :len(tokens)] = tokens
            doc_mask[row, :len(tokens)] = True
        for text in ("The player won the tennis championship.", "The company reported higher revenue and profits."):
            prefix = [manifest["cls_token_id"], *encode("Instruction: "), *encode("Which topic describes this article?"),
                      *encode("\n"), *encode("State: "), *encode(json.dumps({"article": text}, separators=(",", ":"))), manifest["sep_token_id"]]
            prefix_ids = np.array([prefix], dtype=np.int64)
            raw = model.session.run(["logits"], {"prefix_ids": prefix_ids, "prefix_mask": np.ones(prefix_ids.shape, dtype=np.bool_),
                "doc_ids": doc_ids, "doc_mask": doc_mask, "owners": np.zeros(2, dtype=np.int64)})[0]
            column = raw[:, manifest["tasks"].index("choice")]
            print(size, text, "=>", ids[int(np.argmax(column))], "logits", column.tolist())

if __name__ == "__main__":
    main()
